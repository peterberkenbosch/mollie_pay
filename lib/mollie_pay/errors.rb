module MolliePay
  class Error              < StandardError; end
  class MandateRequired    < Error; end
  class SubscriptionNotFound < Error; end
end
