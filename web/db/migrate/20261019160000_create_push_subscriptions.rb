class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    # PRD §16: deleted on explicit sign-out / sign-out-others / Remove / 404-410; session expiry
    # only nullifies session_id, so reminders keep arriving
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :session, foreign_key: { on_delete: :nullify }
      t.string :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.string :user_agent
      t.string :device_label
      t.datetime :last_success_at
      t.datetime :last_receipt_at
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
    add_index :delivery_attempts, :receipt_token_digest, unique: true, where: "receipt_token_digest IS NOT NULL"
  end
end
