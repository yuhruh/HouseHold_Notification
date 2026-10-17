# M0 push spike only (PRD: "Riskiest assumption first"). Replaced by the real
# push_subscriptions / reminder_deliveries tables in M5.
class CreateSpikePushTables < ActiveRecord::Migration[8.1]
  def change
    create_table :spike_push_subscriptions do |t|
      t.string :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.string :user_agent
      t.timestamps
    end
    add_index :spike_push_subscriptions, :endpoint, unique: true

    create_table :spike_push_sends do |t|
      t.references :spike_push_subscription, null: false, foreign_key: { on_delete: :cascade }
      t.string :receipt_token, null: false
      t.datetime :scheduled_for, null: false
      t.datetime :sent_at
      t.integer :http_status
      t.string :error
      t.datetime :received_at
      t.timestamps
    end
    add_index :spike_push_sends, :receipt_token, unique: true
  end
end
