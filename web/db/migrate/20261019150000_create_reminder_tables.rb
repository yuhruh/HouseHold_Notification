class CreateReminderTables < ActiveRecord::Migration[8.1]
  def change
    # Channel toggles per member and household; a missing row means the role default (PRD §6)
    create_table :notification_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :household, null: false, foreign_key: true
      t.boolean :web_push, null: false
      t.boolean :email, null: false
      t.timestamps
    end
    add_index :notification_preferences, %i[user_id household_id], unique: true

    # One digest per member × household × channel × local day (+ at most one same-day addition).
    # in_app deliveries are settled as sent at once; the inbox has no failure state.
    create_table :reminder_deliveries do |t|
      t.references :household, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :channel, null: false
      t.date :run_on, null: false
      t.boolean :addition, null: false, default: false
      t.string :status, null: false, default: "pending"
      t.datetime :dispatched_at
      t.string :error
      t.integer :attempts, null: false, default: 0
      t.datetime :sent_at
      t.datetime :failed_at
      t.references :resent_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :resent_at
      t.datetime :owner_notified_at
      t.timestamps
    end
    add_index :reminder_deliveries, %i[household_id user_id channel run_on addition], unique: true, name: "index_reminder_deliveries_one_per_day"
    add_index :reminder_deliveries, %i[status dispatched_at]
    add_check_constraint :reminder_deliveries, "channel IN ('in_app', 'email', 'web_push')", name: "reminder_deliveries_channel"
    add_check_constraint :reminder_deliveries, "status IN ('pending', 'awaiting_receipt', 'sent', 'failed', 'resolved')", name: "reminder_deliveries_status"

    create_table :delivery_attempts do |t|
      t.references :reminder_delivery, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :push_subscription_id
      t.string :channel, null: false
      t.string :status, null: false
      t.integer :http_status
      t.string :error
      t.string :receipt_token_digest
      t.datetime :attempted_at, null: false
      t.datetime :received_at
    end

    # A row is a claim; its delivery's status is the truth. snoozed rows have no delivery.
    create_table :reminder_logs do |t|
      t.references :record, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :channel, null: false
      t.date :scheduled_on, null: false
      t.boolean :snoozed, null: false, default: false
      t.references :reminder_delivery, foreign_key: { on_delete: :nullify }
      t.datetime :created_at, null: false
    end
    add_index :reminder_logs, %i[record_id user_id kind channel scheduled_on], unique: true, name: "index_reminder_logs_claim"

    create_table :reminder_snoozes do |t|
      t.references :record, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.date :until_on, null: false
      t.datetime :created_at, null: false
    end
    add_index :reminder_snoozes, %i[record_id user_id], unique: true

    # The in-app inbox (PRD → Data model); record_id has no FK so deleted records show "deleted"
    create_table :notifications do |t|
      t.references :household, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body
      t.string :url
      t.bigint :record_id
      t.references :reminder_delivery, foreign_key: { on_delete: :nullify }
      t.datetime :read_at
      t.datetime :created_at, null: false
    end
    add_index :notifications, %i[user_id read_at created_at]
    add_index :notifications, :household_id

    add_column :records, :reminders_restarted_on, :date
  end
end
