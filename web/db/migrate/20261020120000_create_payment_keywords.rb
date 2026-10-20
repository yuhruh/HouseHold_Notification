class CreatePaymentKeywords < ActiveRecord::Migration[8.1]
  def change
    # Payment keyword in record notes → payment method ("從備註指定付款方式"); payment_method null = skip.
    # Lower position wins when a note matches several. Imports reuse the saved choices.
    create_table :payment_keywords do |t|
      t.references :household, null: false, foreign_key: true
      t.string :keyword, null: false
      t.references :payment_method, foreign_key: { on_delete: :nullify }
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :payment_keywords, %i[household_id keyword], unique: true
  end
end
