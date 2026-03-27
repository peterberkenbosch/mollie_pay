module MolliePay
  class Error                < StandardError; end
  class MandateRequired      < Error; end
  class SubscriptionNotFound < Error; end
  class PaymentNotCancelable < Error; end
  class InvalidSignature     < Error; end
  class InvoiceNotUpdatable  < Error; end
end
