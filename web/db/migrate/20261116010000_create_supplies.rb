# Supplies: household consumables with a learned run-out forecast and restock alerts, plus
# barcode and Taiwan e-invoice (發票) scanning. Counts are whole numbers that can't go negative.
class CreateSupplies < ActiveRecord::Migration[8.1]
  def change
    create_table :supplies do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "other"
      t.string :unit, null: false, default: "piece"
      t.integer :level, null: false, default: 0
      t.datetime :level_at, null: false
      t.decimal :usage_per_day, precision: 10, scale: 4
      t.integer :guess_days_per_unit
      t.integer :lead_days, null: false, default: 3
      t.integer :alert_when_left, null: false, default: 0
      t.string :alert_state, null: false, default: "ok"
      t.datetime :alerted_at
      t.datetime :archived_at
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :supplies, "kind IN ('toiletries','cleaning','kitchen','food_drink','health','other')", name: "supplies_kind"
    add_check_constraint :supplies, "unit IN ('piece','roll','bottle','can','pack','box','bag')", name: "supplies_unit"
    add_check_constraint :supplies, "level >= 0", name: "supplies_level_not_negative"
    add_check_constraint :supplies, "alert_when_left >= 0", name: "supplies_alert_when_left_not_negative"
    add_check_constraint :supplies, "lead_days BETWEEN 0 AND 30", name: "supplies_lead_days"
    add_check_constraint :supplies, "guess_days_per_unit IS NULL OR guess_days_per_unit >= 1", name: "supplies_guess_days"
    add_check_constraint :supplies, "alert_state IN ('ok','low','out')", name: "supplies_alert_state"

    create_table :receipt_imports do |t|
      t.references :household, null: false, foreign_key: true
      t.string :invoice_no, null: false
      t.string :seller_tax_id
      t.date :issued_on, null: false
      t.decimal :total, precision: 12, scale: 2, null: false
      t.references :record, foreign_key: { on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :receipt_imports, %i[household_id invoice_no], unique: true

    create_table :supply_purchases do |t|
      t.references :household, null: false, foreign_key: true
      t.references :supply, null: false, foreign_key: true
      t.date :purchased_on, null: false
      t.integer :quantity, null: false
      t.decimal :total_price, precision: 12, scale: 2, null: false
      t.string :currency, null: false, default: "TWD"
      t.string :store
      t.date :expires_on
      t.integer :left_before, null: false
      t.references :record, foreign_key: { on_delete: :nullify }
      t.references :receipt_import, foreign_key: { on_delete: :nullify }
      t.datetime :expiry_alerted_at
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_check_constraint :supply_purchases, "quantity > 0", name: "supply_purchases_quantity_positive"
    add_check_constraint :supply_purchases, "total_price >= 0", name: "supply_purchases_total_not_negative"
    add_check_constraint :supply_purchases, "left_before >= 0", name: "supply_purchases_left_before_not_negative"

    create_table :supply_counts do |t|
      t.references :supply, null: false, foreign_key: true
      t.datetime :counted_at, null: false
      t.integer :level, null: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :created_at, null: false
    end
    add_check_constraint :supply_counts, "level >= 0", name: "supply_counts_level_not_negative"

    create_table :supply_barcodes do |t|
      t.references :household, null: false, foreign_key: true
      t.references :supply, null: false, foreign_key: true
      t.string :code, null: false
      t.datetime :created_at, null: false
    end
    add_index :supply_barcodes, %i[household_id code], unique: true

    # Public product facts only (no household data), shared by every household
    create_table :product_lookups do |t|
      t.string :code, null: false, index: { unique: true }
      t.string :source
      t.string :name
      t.string :original_name
      t.string :brand
      t.string :kind_guess
      t.jsonb :raw, null: false, default: {}
      t.datetime :fetched_at, null: false
    end

    create_table :receipt_sellers do |t|
      t.references :household, null: false, foreign_key: true
      t.string :tax_id, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :receipt_sellers, %i[household_id tax_id], unique: true

    # What a receipt line from a store meant last time: a supply (or skip, when supply_id is null)
    create_table :receipt_item_matches do |t|
      t.references :household, null: false, foreign_key: true
      t.string :seller_tax_id, null: false, default: ""
      t.string :receipt_text, null: false
      t.references :supply, foreign_key: { on_delete: :nullify }
      t.integer :units_per_line, null: false, default: 1
      t.timestamps
    end
    add_index :receipt_item_matches, %i[household_id seller_tax_id receipt_text], unique: true, name: "index_receipt_item_matches_unique"
    add_check_constraint :receipt_item_matches, "units_per_line >= 1", name: "receipt_item_matches_units_positive"

    # "Supplies running low or expiring": nil follows the role, like bill_paid
    add_column :notification_preferences, :supply_alert, :boolean
  end
end
