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
