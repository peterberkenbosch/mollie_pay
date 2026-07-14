module MolliePay
  # UUIDv7 string primary keys for all MolliePay models. Copied verbatim across
  # the engine family (reservr, hunion) per the engine-family charter — the
  # engines share the convention, never a gem. UUIDv7 is time-ordered, so it
  # indexes well as a PK while staying merge/replica-safe.
  module HasUuid
    extend ActiveSupport::Concern

    included do
      before_create :set_uuid
    end

    private

    def set_uuid
      self.id ||= SecureRandom.uuid_v7
    end
  end
end
