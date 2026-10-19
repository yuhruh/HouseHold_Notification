class CreateRecords < ActiveRecord::Migration[8.1]
  def change
    # Counter for records.record_no (never reused, PRD → Data model)
    add_column :households, :next_record_no, :integer, null: false, default: 0

    # recurring_template_id and import_batch_id arrive with their tables (M4, M2 import commit)
    create_table :records do |t|
      t.references :household, null: false, foreign_key: true, index: false
      t.string :record_type, null: false
      t.references :category, null: false, foreign_key: true
      t.string :title, null: false
      t.string :details
      t.integer :period_year, null: false
      t.integer :period_start_month, null: false
      t.integer :period_end_year, null: false
      t.integer :period_end_month, null: false
      t.string :currency, null: false, default: "TWD"
      t.decimal :amount_required, precision: 12, scale: 2
      t.decimal :amount_paid, precision: 12, scale: 2
      t.boolean :settled, null: false, default: false
      t.date :due_on
      t.date :paid_on
      t.references :payment_method, foreign_key: { on_delete: :nullify }
      t.text :payment_note
      t.date :next_due_on
      t.string :reminder_frequency, null: false, default: "none"
      t.date :reminder_starts_on
      t.integer :record_no, null: false
      t.string :import_key
      t.string :import_digest
      t.datetime :imported_at
      t.jsonb :import_snapshot
      t.integer :lock_version, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end
    add_index :records, %i[household_id period_year record_type]
    add_index :records, %i[household_id due_on], where: "settled = false"
    add_index :records, %i[household_id reminder_frequency], where: "due_on IS NULL AND settled = false"
    add_index :records, %i[household_id next_due_on], where: "next_due_on IS NOT NULL"
    add_index :records, %i[household_id record_no], unique: true
    add_index :records, %i[household_id import_key], unique: true
    add_check_constraint :records, "record_type IN ('expense', 'maintenance', 'tax')", name: "records_record_type"
    add_check_constraint :records, "currency IN ('TWD', 'USD')", name: "records_currency"
    add_check_constraint :records, "amount_required IS NULL OR amount_required >= 0", name: "records_amount_required_nonnegative"
    add_check_constraint :records, "amount_paid IS NULL OR amount_paid >= 0", name: "records_amount_paid_nonnegative"
    add_check_constraint :records, "period_start_month BETWEEN 1 AND 12 AND period_end_month BETWEEN 1 AND 12", name: "records_period_months"
    add_check_constraint :records,
      "reminder_frequency IN ('none', 'daily', 'every_3_days', 'weekly', 'biweekly', 'monthly')", name: "records_reminder_frequency"
  end
end
