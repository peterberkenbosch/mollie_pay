require "test_helper"

module MolliePay
  class RequestSignatureTest < ActiveSupport::TestCase
    setup do
      @key = OpenSSL::PKey.generate_key("ED25519")
      @public_key = OpenSSL::PKey.read(@key.public_to_pem)
    end

    teardown do
      MolliePay.configuration.request_signing_key = nil
    end

    test "the payload joins method, path, query, timestamp, idempotency key and body hash" do
      request = Net::HTTP::Post.new("/v2/payments")
      request.body = '{"amount":{"currency":"EUR","value":"10.00"}}'
      request["Idempotency-Key"] = "idem-123"

      payload = RequestSignature.payload(request, "2026-10-13T10:30:00.123Z")

      assert_equal [
        "post",
        "/v2/payments",
        "",
        "2026-10-13T10:30:00.123Z",
        "idem-123",
        Digest::SHA256.hexdigest('{"amount":{"currency":"EUR","value":"10.00"}}')
      ].join("\n"), payload
    end

    test "the payload of a request without body or idempotency key hashes an empty body" do
      payload = RequestSignature.payload(Net::HTTP::Get.new("/v2/payments/tr_1"), "2026-10-13T10:30:00.123Z")

      assert_equal "get\n/v2/payments/tr_1\n\n2026-10-13T10:30:00.123Z\n\n#{Digest::SHA256.hexdigest('')}", payload
    end

    test "the query is sorted by key and encoded like encodeURIComponent" do
      request = Net::HTTP::Get.new("/v2/payments?limit=5&from=tr_1&description=a+b%21%2A")

      assert_equal "/v2/payments", RequestSignature.payload(request, "t").lines[1].chomp
      assert_equal "description=a%20b!*&from=tr_1&limit=5", RequestSignature.payload(request, "t").lines[2].chomp
    end

    test "sign! adds a millisecond UTC timestamp and an Ed25519 signature of the payload" do
      request = Net::HTTP::Post.new("/v2/payments")
      request.body = "{}"

      travel_to Time.utc(2026, 10, 13, 10, 30, Rational(123, 1000)), with_usec: true do
        RequestSignature.sign!(request, @key)
      end

      assert_equal "2026-10-13T10:30:00.123Z", request["X-Client-Signed-At"]
      signature = Base64.strict_decode64(request["X-Client-Signature"])
      assert @public_key.verify(nil, signature, RequestSignature.payload(request, request["X-Client-Signed-At"]))
    end

    test "SDK requests carry a valid signature when a signing key is configured" do
      MolliePay.configuration.request_signing_key = @key.private_to_pem
      signed = nil
      stub_request(:post, "#{MOLLIE_API_BASE}/payments").to_return do |request|
        signed = request
        { status: 201, headers: { "Content-Type" => "application/hal+json" }, body: { resource: "payment", id: "tr_signed" }.to_json }
      end

      Mollie::Payment.create(amount: { currency: "EUR", value: "10.00" }, description: "Signed", idempotency_key: "idem-signed")

      payload = [
        "post", "/v2/payments", "", signed.headers["X-Client-Signed-At"], "idem-signed", Digest::SHA256.hexdigest(signed.body)
      ].join("\n")
      assert @public_key.verify(nil, Base64.strict_decode64(signed.headers["X-Client-Signature"]), payload)
    end

    test "SDK requests carry no signature when no signing key is configured" do
      unsigned = nil
      stub_request(:get, "#{MOLLIE_API_BASE}/payments/tr_unsigned").to_return do |request|
        unsigned = request
        { status: 200, headers: { "Content-Type" => "application/hal+json" }, body: { resource: "payment", id: "tr_unsigned" }.to_json }
      end

      Mollie::Payment.get("tr_unsigned")

      assert_nil unsigned.headers["X-Client-Signature"]
      assert_nil unsigned.headers["X-Client-Signed-At"]
    end

    test "a signing key that is not Ed25519 is refused" do
      MolliePay.configuration.request_signing_key = OpenSSL::PKey::RSA.generate(2048).to_pem

      assert_raises(MolliePay::ConfigurationError) { MolliePay.configuration.request_signing_private_key }
    end
  end
end
