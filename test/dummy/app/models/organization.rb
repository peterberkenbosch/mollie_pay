class Organization < ApplicationRecord
  include MolliePay::Billable

  # UUIDv7 string PK, mirroring an engine-family charter host (User).
  before_create { self.id ||= SecureRandom.uuid_v7 }
end
