module MolliePay
  # Casts a TEXT-affinity :string column to and from exact BigDecimal money.
  # SQLite has no real DECIMAL type: a :decimal column gets NUMERIC affinity and
  # silently stores REAL/float, losing precision. Storing the amount as text and
  # casting here keeps it exact. Serializes to fixed-point text (never scientific
  # notation) so SQLite keeps TEXT affinity and round-trips exactly.
  class DecimalMoneyType < ActiveRecord::Type::Decimal
    def serialize(value)
      return nil if value.nil?

      BigDecimal(value.to_s).to_s("F") # "19.99", never "0.1999e2"
    end
  end
end
