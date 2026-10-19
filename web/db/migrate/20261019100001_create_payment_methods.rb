class CreatePaymentMethods < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_methods do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "other"
      t.string :last4
      t.datetime :archived_at

      t.timestamps
    end
    add_check_constraint :payment_methods, "kind IN ('card', 'bank', 'e_wallet', 'cash', 'other')", name: "payment_methods_kind"
  end
end
