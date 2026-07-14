class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    # UUIDv7 string PK so the polymorphic MolliePay owner (:string) is exercised
    # with real string host ids, matching an engine-family charter host (User).
    create_table :organizations, id: :string do |t|
      t.string :name
      t.string :email
      t.timestamps
    end
  end
end
