require "test_helper"

module MolliePay
  # Mollie reaches a single subscription, refund or chargeback only through its
  # parent: /v2/customers/:id/subscriptions/:id and /v2/payments/:id/refunds.
  # The SDK's top-level classes build /v2/subscriptions/:id and /v2/refunds
  # anyway, because Mollie::Base.resource_name nests the path only for
  # two-level classes, and send the parent id as a parameter. Mollie answers
  # 404. See issue #135.
  class SdkResourcePathsTest < ActiveSupport::TestCase
    TOP_LEVEL_CALL = /Mollie::(Subscription|Refund|Chargeback)\.(get|create|update|delete|cancel)\b/

    test "engine code calls nested Mollie resources through their parent class" do
      root = MolliePay::Engine.root
      offenders = Dir[root.join("{app,lib}/**/*.rb")].flat_map do |path|
        File.readlines(path).each_with_index.filter_map do |line, index|
          "#{Pathname(path).relative_path_from(root)}:#{index + 1}: #{line.strip}" if line.match?(TOP_LEVEL_CALL)
        end
      end

      assert_empty offenders, <<~MESSAGE
        Use Mollie::Customer::Subscription, Mollie::Payment::Refund or Mollie::Payment::Chargeback.
        The top-level class builds a path Mollie does not have:
        #{offenders.join("\n")}
      MESSAGE
    end
  end
end
