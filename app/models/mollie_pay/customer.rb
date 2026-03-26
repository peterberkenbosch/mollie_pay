module MolliePay
  class Customer < ApplicationRecord
    belongs_to :owner, polymorphic: true

    has_many :payments,       dependent: :destroy
    has_many :subscriptions,  dependent: :destroy
    has_many :mandates,       dependent: :destroy
    has_many :sales_invoices, dependent: :destroy

    validates :mollie_id, presence: true, uniqueness: true

    def mollie_record
      Mollie::Customer.get(mollie_id)
    end

    def active_subscription
      subscriptions.active.first
    end

    def valid_mandate
      mandates.valid_status.first
    end

    def subscribed?
      subscriptions.active.exists?
    end

    def mandated?
      mandates.valid_status.exists?
    end
  end
end
