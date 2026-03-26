module Mollie
  class SalesInvoice < Base
    STATUS_DRAFT    = "draft".freeze
    STATUS_ISSUED   = "issued".freeze
    STATUS_PAID     = "paid".freeze
    STATUS_CANCELED = "canceled".freeze

    attr_accessor :id,
                  :profile_id,
                  :status,
                  :invoice_number,
                  :recipient_identifier,
                  :recipient,
                  :lines,
                  :payment_term,
                  :vat_scheme,
                  :vat_mode,
                  :memo,
                  :metadata,
                  :is_e_invoice,
                  :email_details,
                  :payment_details,
                  :subtotal_amount,
                  :discounted_subtotal_amount,
                  :total_vat_amount,
                  :total_amount,
                  :amount_due,
                  :created_at,
                  :issued_at,
                  :paid_at,
                  :due_at,
                  :_links

    alias links _links

    def self.resource_name(_parent_id = nil)
      "sales-invoices"
    end

    def draft?
      status == STATUS_DRAFT
    end

    def issued?
      status == STATUS_ISSUED
    end

    def paid?
      status == STATUS_PAID
    end

    def canceled?
      status == STATUS_CANCELED
    end

    def pdf_url
      Util.extract_url(links, "pdf_link")
    end

    def payment_url
      Util.extract_url(links, "invoice_payment")
    end

    def subtotal_amount=(amount)
      @subtotal_amount = Amount.new(amount) if amount
    end

    def discounted_subtotal_amount=(amount)
      @discounted_subtotal_amount = Amount.new(amount) if amount
    end

    def total_vat_amount=(amount)
      @total_vat_amount = Amount.new(amount) if amount
    end

    def total_amount=(amount)
      @total_amount = Amount.new(amount) if amount
    end

    def amount_due=(amount)
      @amount_due = Amount.new(amount) if amount
    end

    def created_at=(value)
      @created_at = begin
                      Time.parse(value.to_s)
                    rescue StandardError
                      nil
                    end
    end

    def issued_at=(value)
      @issued_at = begin
                     Time.parse(value.to_s)
                   rescue StandardError
                     nil
                   end
    end

    def paid_at=(value)
      @paid_at = begin
                   Time.parse(value.to_s)
                 rescue StandardError
                   nil
                 end
    end

    def due_at=(value)
      @due_at = begin
                  Time.parse(value.to_s)
                rescue StandardError
                  nil
                end
    end

    def recipient=(recipient)
      @recipient = OpenStruct.new(recipient) if recipient.is_a?(Hash)
    end

    def metadata=(metadata)
      @metadata = OpenStruct.new(metadata) if metadata.is_a?(Hash)
    end
  end
end
