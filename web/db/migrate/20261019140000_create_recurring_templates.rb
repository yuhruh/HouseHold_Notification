class CreateRecurringTemplates < ActiveRecord::Migration[8.1]
  def change
    # PRD §5. due_month_offset (months from period start to the due month) is our addition:
    # due_day alone can't say "the 1月–2月 water bill is due in March".
    create_table :recurring_templates do |t|
      t.references :household, null: false, foreign_key: true
      t.string :record_type, null: false
      t.references :category, null: false, foreign_key: true
      t.string :title, null: false
      t.string :details
      t.string :currency, null: false, default: "TWD"
      t.decimal :default_amount, precision: 12, scale: 2
      t.boolean :amount_fixed, null: false, default: false
      t.integer :interval_months, null: false
      t.integer :anchor_month, null: false
      t.integer :period_span_months, null: false
      t.date :starts_on, null: false
      t.integer :due_day
      t.integer :due_month_offset, null: false, default: 0
      t.integer :lead_days, null: false, default: 7
      t.string :default_reminder_frequency, null: false, default: "none"
      t.references :payment_method, foreign_key: { on_delete: :nullify }

      t.timestamps
    end
    add_check_constraint :recurring_templates, "record_type IN ('expense', 'maintenance', 'tax')", name: "recurring_templates_record_type"
    add_check_constraint :recurring_templates, "interval_months BETWEEN 1 AND 60", name: "recurring_templates_interval"
    add_check_constraint :recurring_templates, "anchor_month BETWEEN 1 AND 12", name: "recurring_templates_anchor"
    add_check_constraint :recurring_templates, "period_span_months BETWEEN 1 AND 12", name: "recurring_templates_span"
    add_check_constraint :recurring_templates, "due_day IS NULL OR due_day BETWEEN 1 AND 31", name: "recurring_templates_due_day"
    add_check_constraint :recurring_templates, "due_month_offset BETWEEN 0 AND 24", name: "recurring_templates_due_offset"
    add_check_constraint :recurring_templates, "lead_days BETWEEN 0 AND 90", name: "recurring_templates_lead_days"

    add_reference :records, :recurring_template, foreign_key: { on_delete: :nullify }, index: false
    add_index :records, %i[recurring_template_id period_year period_start_month], unique: true,
      where: "recurring_template_id IS NOT NULL", name: "index_records_one_per_template_period"

    remove_check_constraint :record_events,
      "action IN ('created', 'updated', 'deleted', 'marked_paid', 'import_created', 'import_updated', 'import_undone')",
      name: "record_events_action"
    add_check_constraint :record_events,
      "action IN ('created', 'updated', 'deleted', 'marked_paid', 'import_created', 'import_updated', 'import_undone', " \
      "'template_updated', 'reminders_restarted')", name: "record_events_action"
  end
end
