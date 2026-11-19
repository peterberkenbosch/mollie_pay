module MolliePay
  class SalesInvoice < ApplicationRecord
    STATUS_DRAFT    = "draft"
    STATUS_ISSUED   = "issued"
    STATUS_PAID     = "paid"
    STATUS_CANCELED = "cancelled" # Mollie's spelling

    # Mollie's statuses, in the order of its API reference.
    STATUSES = [
      STATUS_DRAFT, "issuing", STATUS_ISSUED, "pending-payment", STATUS_PAID,
      "overdue", "payment-reversed", STATUS_CANCELED, "expired", "failed"
    ].freeze

    belongs_to :customer


    validates :mollie_id, presence: true, uniqueness: true
    validates :status,    inclusion: { in: STATUSES }
    validates :amount,    numericality: { greater_than: 0 }, allow_nil: true
    validate  :amount_within_precision
    validates :currency,  presence: true, allow_nil: true

    scope :draft,   -> { where(status: STATUS_DRAFT) }
    scope :issued,  -> { where(status: STATUS_ISSUED) }
    scope :paid,    -> { where(status: STATUS_PAID) }
    scope :overdue, -> { where(status: STATUS_ISSUED).where("due_at < ?", Time.current) }

    def self.record_from_mollie(mollie_si, customer)
      invoice = find_or_initialize_by(mollie_id: mollie_si.id)
      previous_status = invoice.status

      amount   = mollie_si.total_amount ? mollie_value_to_decimal(mollie_si.total_amount) : nil
      currency = mollie_si.total_amount&.currency

      invoice.update!(
        customer:             customer,
        status:               mollie_si.status,
        invoice_number:       mollie_si.invoice_number,
        amount:               amount,
        currency:             currency,
        recipient_identifier: mollie_si.recipient_identifier,
        memo:                 mollie_si.memo,
        issued_at:            mollie_si.issued_at,
        paid_at:              mollie_si.paid_at,
        due_at:               mollie_si.due_at
      )

      if invoice.status != previous_status
        notify_billable(invoice, previous_status)
      end

      invoice
    rescue ActiveRecord::RecordNotUnique
      find_by!(mollie_id: mollie_si.id)
    end

    def mollie_record
      Mollie::SalesInvoice.get(mollie_id)
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

    def mollie_amount
      MolliePay.mollie_amount(amount, currency: currency)
    end

    private_class_method def self.notify_billable(invoice, previous_status)
      billable = invoice.customer.owner

      if invoice.status == STATUS_ISSUED && previous_status != STATUS_ISSUED
        billable.on_mollie_sales_invoice_issued(invoice)
      end

      if invoice.status == STATUS_PAID && previous_status != STATUS_PAID
        billable.on_mollie_sales_invoice_paid(invoice)
      end
    end
  end
end
