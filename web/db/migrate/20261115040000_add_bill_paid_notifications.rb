# "Bill paid" notifications: a per-member toggle (nil follows the role, like the channels), push
# receipts that belong to a notification instead of a reminder digest, and when the fallback
# email went (so it goes once).
class AddBillPaidNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notification_preferences, :bill_paid, :boolean
    add_column :notifications, :fallback_emailed_at, :datetime

    change_column_null :delivery_attempts, :reminder_delivery_id, true
    add_reference :delivery_attempts, :notification, foreign_key: { on_delete: :cascade }
    add_check_constraint :delivery_attempts, "num_nonnulls(reminder_delivery_id, notification_id) = 1", name: "delivery_attempts_one_owner"
  end
end
