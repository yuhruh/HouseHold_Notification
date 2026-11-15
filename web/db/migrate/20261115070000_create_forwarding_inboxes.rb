# The forwarding address moves from Electricity to the ledger, so 台電 and 台水 emails share it.
# Each Electricity account's token (and who may forward, Gmail's confirmation, the setup emails
# sent) is copied as is, so addresses already set up in Gmail keep working.
class CreateForwardingInboxes < ActiveRecord::Migration[8.1]
  ACTIONS = %w[created updated deleted marked_paid import_created import_updated import_undone template_updated reminders_restarted
    gas_synced gas_paid taipower_synced taipower_paid].map { "'#{it}'" }.join(", ").freeze
  MOVED = %w[inbox_token allowed_senders setup_emails_sent forwarding_link forwarding_code forwarding_from forwarding_code_at].freeze

  def up
    create_table :forwarding_inboxes do |t|
      t.references :household, null: false, foreign_key: true, index: { unique: true }
      t.string :inbox_token, null: false, index: { unique: true }
      t.string :allowed_senders, array: true, default: [], null: false
      t.jsonb :setup_emails_sent, default: {}, null: false
      t.text :forwarding_link
      t.string :forwarding_code
      t.string :forwarding_from
      t.datetime :forwarding_code_at
      t.timestamps
    end

    execute <<~SQL
      INSERT INTO forwarding_inboxes (household_id, #{MOVED.join(", ")}, created_at, updated_at)
      SELECT household_id, #{MOVED.join(", ")}, created_at, NOW()
      FROM utility_accounts WHERE type = 'ElectricityAccount' AND inbox_token IS NOT NULL
    SQL

    remove_index :utility_accounts, :inbox_token
    MOVED.each { remove_column :utility_accounts, it }

    remove_check_constraint :utility_accounts, name: "utility_accounts_type"
    add_check_constraint :utility_accounts, "type IN ('GasAccount', 'ElectricityAccount', 'WaterAccount')", name: "utility_accounts_type"

    # 台水's lines in a bill's history
    remove_check_constraint :record_events, name: "record_events_action"
    add_check_constraint :record_events, "action IN (#{ACTIONS}, 'water_synced', 'water_paid')", name: "record_events_action"
  end

  def down
    execute "DELETE FROM record_events WHERE action IN ('water_synced', 'water_paid')"
    remove_check_constraint :record_events, name: "record_events_action"
    add_check_constraint :record_events, "action IN (#{ACTIONS})", name: "record_events_action"
    execute "DELETE FROM utility_accounts WHERE type = 'WaterAccount'"
    remove_check_constraint :utility_accounts, name: "utility_accounts_type"
    add_check_constraint :utility_accounts, "type IN ('GasAccount', 'ElectricityAccount')", name: "utility_accounts_type"

    add_column :utility_accounts, :inbox_token, :string
    add_column :utility_accounts, :allowed_senders, :string, array: true, default: [], null: false
    add_column :utility_accounts, :setup_emails_sent, :jsonb, default: {}, null: false
    add_column :utility_accounts, :forwarding_link, :text
    add_column :utility_accounts, :forwarding_code, :string
    add_column :utility_accounts, :forwarding_from, :string
    add_column :utility_accounts, :forwarding_code_at, :datetime
    add_index :utility_accounts, :inbox_token, unique: true
    execute <<~SQL
      UPDATE utility_accounts u SET #{MOVED.map { "#{it} = f.#{it}" }.join(", ")}
      FROM forwarding_inboxes f WHERE f.household_id = u.household_id AND u.type = 'ElectricityAccount'
    SQL
    drop_table :forwarding_inboxes
  end
end
