# Gas accounts become one kind of utility account; electricity (台電) is the other. Single-table
# inheritance on `type` (GasAccount / ElectricityAccount): one of each per ledger. 台電's 電號 is
# optional (the first forwarded bill email sets it), so customer_code may be empty. `inbox_token`
# makes the ledger's forwarding address; `allowed_senders` lists extra emails that may forward to it;
# forwarding_* hold Gmail's confirmation code for that address.
class CreateUtilityAccounts < ActiveRecord::Migration[8.1]
  OLD_ACTIONS = "'created', 'updated', 'deleted', 'marked_paid', 'import_created', 'import_updated', 'import_undone', " \
    "'template_updated', 'reminders_restarted', 'gas_synced', 'gas_paid'".freeze

  def change
    rename_table :gas_accounts, :utility_accounts

    add_column :utility_accounts, :type, :string, null: false, default: "GasAccount"
    change_column_default :utility_accounts, :type, from: "GasAccount", to: nil
    add_check_constraint :utility_accounts, "type IN ('GasAccount', 'ElectricityAccount')", name: "utility_accounts_type"
    change_column_null :utility_accounts, :customer_code, true
    add_column :utility_accounts, :inbox_token, :string
    add_column :utility_accounts, :allowed_senders, :string, array: true, null: false, default: []
    add_index :utility_accounts, :inbox_token, unique: true
    # Gmail's forwarding confirmation code for that address, shown on the page for the member to type in
    add_column :utility_accounts, :forwarding_code, :string
    add_column :utility_accounts, :forwarding_from, :string
    add_column :utility_accounts, :forwarding_code_at, :datetime

    remove_index :utility_accounts, :household_id, unique: true
    add_index :utility_accounts, %i[household_id type], unique: true
    remove_index :utility_accounts, :customer_code, unique: true
    add_index :utility_accounts, %i[type customer_code], unique: true, where: "customer_code IS NOT NULL"

    # 台電's lines in a bill's history (from forwarded emails)
    remove_check_constraint :record_events, "action IN (#{OLD_ACTIONS})", name: "record_events_action"
    add_check_constraint :record_events, "action IN (#{OLD_ACTIONS}, 'taipower_synced', 'taipower_paid')", name: "record_events_action"
  end
end
