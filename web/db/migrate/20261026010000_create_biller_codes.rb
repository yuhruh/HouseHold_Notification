# Bill barcodes (三段式條碼): each household remembers which category a biller code means, and whether
# the barcode's deadline is the due date or a few days after it (taxes: 3 days after). Records keep the
# bill number (銷帳編號) so scanning the same bill again can warn.
class CreateBillerCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :biller_codes do |t|
      t.references :household, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string :code, null: false
      t.integer :deadline_offset_days, null: false, default: 0
      t.timestamps
    end
    add_index :biller_codes, %i[household_id code], unique: true
    add_check_constraint :biller_codes, "deadline_offset_days BETWEEN 0 AND 10", name: "biller_codes_offset_range"

    add_column :records, :bill_number, :string
    add_index :records, %i[household_id bill_number], where: "bill_number IS NOT NULL"
  end
end
