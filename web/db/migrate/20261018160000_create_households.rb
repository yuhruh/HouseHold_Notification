class CreateHouseholds < ActiveRecord::Migration[8.1]
  def change
    # No time zone: Household#time_zone is the owner's (PRD §11)
    create_table :households do |t|
      t.string :name, null: false
      t.string :default_currency, null: false, default: "TWD"
      t.integer :reminder_lead_days, null: false, default: 3
      t.date :last_failure_summary_on

      t.timestamps
    end
    add_check_constraint :households, "reminder_lead_days BETWEEN 0 AND 30", name: "households_reminder_lead_days_range"
    add_check_constraint :households, "default_currency IN ('TWD', 'USD')", name: "households_default_currency"
  end
end
