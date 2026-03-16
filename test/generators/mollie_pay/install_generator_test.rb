require "test_helper"
require "rails/generators/test_case"
require "generators/mollie_pay/install/install_generator"

class MolliePay::Generators::InstallGeneratorTest < Rails::Generators::TestCase
  tests MolliePay::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator_test", __dir__)

  setup do
    prepare_destination
  end

  test "copies the initializer template" do
    run_generator [ "--skip-migrations" ]

    assert_file "config/initializers/mollie_pay.rb" do |content|
      assert_match(/MolliePay\.configure/, content)
      assert_match(/config\.api_key/, content)
      assert_match(/config\.host/, content)
      assert_match(/config\.default_redirect_path/, content)
      assert_match(/config\.currency/, content)
    end
  end
end
