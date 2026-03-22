require "test_helper"

class MolliePay::PaymentMethodsTest < ActiveSupport::TestCase
  test "payment_methods returns available methods" do
    methods_list = [ stub_mollie_method("ideal", "iDEAL") ]
    Mollie::Method.stub(:all, methods_list) do
      result = MolliePay.payment_methods
      assert_equal 1, result.size
      assert_equal "ideal", result.first.id
    end
  end

  test "payment_methods passes amount as Mollie format" do
    called_with = nil
    fake_all = ->(params) { called_with = params; [] }

    Mollie::Method.stub(:all, fake_all) do
      MolliePay.payment_methods(amount: 1000)
    end

    assert_equal({ currency: "EUR", value: "10.00" }, called_with[:amount])
  end

  test "payment_methods passes currency override" do
    called_with = nil
    fake_all = ->(params) { called_with = params; [] }

    Mollie::Method.stub(:all, fake_all) do
      MolliePay.payment_methods(amount: 500, currency: "USD")
    end

    assert_equal "USD", called_with[:amount][:currency]
  end

  test "payment_methods passes locale" do
    called_with = nil
    fake_all = ->(params) { called_with = params; [] }

    Mollie::Method.stub(:all, fake_all) do
      MolliePay.payment_methods(locale: "nl_NL")
    end

    assert_equal "nl_NL", called_with[:locale]
  end

  test "payment_methods does not include amount when not provided" do
    called_with = nil
    fake_all = ->(params) { called_with = params; [] }

    Mollie::Method.stub(:all, fake_all) do
      MolliePay.payment_methods
    end

    assert_nil called_with[:amount]
  end

  test "payment_methods forwards extra options" do
    called_with = nil
    fake_all = ->(params) { called_with = params; [] }

    Mollie::Method.stub(:all, fake_all) do
      MolliePay.payment_methods(include: "pricing")
    end

    assert_equal "pricing", called_with[:include]
  end

  test "payment_method returns single method by id" do
    method = stub_mollie_method("ideal", "iDEAL")
    Mollie::Method.stub(:get, method) do
      result = MolliePay.payment_method("ideal")
      assert_equal "ideal", result.id
      assert_equal "iDEAL", result.description
    end
  end

  test "payment_method forwards options" do
    called_with_id = nil
    called_with_opts = nil
    fake_get = ->(id, opts) { called_with_id = id; called_with_opts = opts; stub_mollie_method(id, "Test") }

    Mollie::Method.stub(:get, fake_get) do
      MolliePay.payment_method("ideal", locale: "nl_NL")
    end

    assert_equal "ideal", called_with_id
    assert_equal({ locale: "nl_NL" }, called_with_opts)
  end

  private

    def stub_mollie_method(id, description)
      OpenStruct.new(id: id, description: description, status: "activated")
    end
end
