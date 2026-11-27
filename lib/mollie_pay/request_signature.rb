require "base64"
require "digest"
require "net/http"
require "openssl"

module MolliePay
  # Signs requests to the Mollie API as https://docs.mollie.com/reference/request-signing
  # describes. Once a public key is registered on a Mollie API key or access
  # token, Mollie rejects every unsigned request made with it.
  #
  # mollie-api-ruby builds and sends each request inside
  # Mollie::Client#perform_http_call and offers no hook in between, so the
  # signature is added in Net::HTTP#request, and only for requests sent from
  # inside that call.
  module RequestSignature
    THREAD_KEY = :mollie_pay_request_signing_key

    module_function

    def sign!(request, key)
      signed_at = Time.current.utc.iso8601(3)
      signature = key.sign(nil, payload(request, signed_at))

      request["X-Client-Signed-At"] = signed_at
      request["X-Client-Signature"] = Base64.strict_encode64(signature)
    end

    def payload(request, signed_at)
      path, query = request.path.split("?", 2)

      [
        request.method.downcase,
        path,
        canonical_query(query),
        signed_at,
        request["Idempotency-Key"].to_s,
        Digest::SHA256.hexdigest(request.body.to_s)
      ].join("\n")
    end

    def canonical_query(query)
      return "" if query.blank?

      URI.decode_www_form(query)
        .each_with_index.sort_by { |(key, _), index| [ key, index ] }
        .map { |(key, value), _| "#{encode_uri_component(key)}=#{encode_uri_component(value)}" }
        .join("&")
    end

    # Matches JavaScript's encodeURIComponent, which Mollie's example uses.
    def encode_uri_component(string)
      string.b.gsub(/[^A-Za-z0-9\-_.!~*'()]/n) { |char| format("%%%02X", char.ord) }
    end

    # A new Ed25519 key pair as PEM: the private key for the app, the public
    # key for Mollie.
    def generate_key_pair
      key = OpenSSL::PKey.generate_key("ED25519")

      [ key.private_to_pem, key.public_to_pem ]
    end

    # The key as the one line of base64 between a PEM's first and last line.
    def single_line(pem)
      pem.lines.reject { |line| line.start_with?("-----") }.join.delete("\n")
    end

    # Reads a key from PEM, from PEM with "\n" for its line breaks, or from
    # the single line. Raises OpenSSL::PKey::PKeyError for anything else.
    def read_key(value)
      text = value.to_s.gsub("\\n", "\n").strip
      text = Base64.decode64(text) unless text.include?("-----BEGIN")

      OpenSSL::PKey.read(text)
    end

    def private?(key)
      key.private_to_der.present?
    rescue OpenSSL::PKey::PKeyError
      false
    end

    # Asks Mollie how this app's signing stands, with two requests that read
    # and change nothing:
    #
    #   :not_configured  no request_signing_key is set
    #   :not_enforced    Mollie accepts an unsigned request, so no public key
    #                    is registered on the API key
    #   :accepted        Mollie refuses unsigned requests and accepts ours
    #   :refused         Mollie refuses unsigned requests and ours too: the
    #                    registered public key is not this key's, the API key
    #                    is wrong, or the clock is more than 5 minutes off
    def status
      if MolliePay.configuration.request_signing_private_key.nil?
        :not_configured
      elsif unsigned_request_accepted?
        :not_enforced
      elsif signed_request_accepted?
        :accepted
      else
        :refused
      end
    end

    # Sent outside Mollie::Client, so nothing signs it.
    def unsigned_request_accepted?
      request = Net::HTTP::Get.new("/#{Mollie::Client::API_VERSION}/methods")
      request["Authorization"] = "Bearer #{MolliePay.configuration.api_key}"
      request["Accept"] = "application/json"
      endpoint = URI(Mollie::Client::API_ENDPOINT)

      response = Net::HTTP.start(endpoint.host, endpoint.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(request) }

      case response.code
      when "200" then true
      when "401" then false
      else raise MolliePay::Error, "Mollie answered #{response.code} to the unsigned request"
      end
    end

    def signed_request_accepted?
      Mollie::Method.all
      true
    rescue Mollie::RequestError => error
      raise unless error.status == 401

      false
    end

    # Prepended into Mollie::Client.
    module Client
      def perform_http_call(...)
        key = MolliePay.configuration.request_signing_private_key
        return super if key.nil?

        # WebMock and similar libraries replace Net::HTTP with a subclass, so
        # the signer goes in front of whichever class is current.
        Net::HTTP.prepend(HTTP) unless Net::HTTP.ancestors.take_while { |ancestor| ancestor != Net::HTTP }.include?(HTTP)

        previous = Thread.current[THREAD_KEY]
        Thread.current[THREAD_KEY] = key
        super
      ensure
        Thread.current[THREAD_KEY] = previous if key
      end
    end

    # Prepended into Net::HTTP. Net::HTTP#request calls itself once more when
    # it opens the connection, so a request is signed only once.
    module HTTP
      def request(request, ...)
        key = Thread.current[THREAD_KEY]
        RequestSignature.sign!(request, key) if key && request["X-Client-Signature"].nil?
        super
      end
    end
  end
end
