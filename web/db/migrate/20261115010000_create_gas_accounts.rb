# Gas bills from 欣桃天然氣: one 用戶編號 per ledger, checked every working day. A bill the sync
# created or adopted carries `external_ref` so it's never added twice.
class CreateGasAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :gas_accounts do |t|
      t.references :household, null: false, foreign_key: true, index: { unique: true }
      t.string :customer_code, null: false, index: { unique: true }
      t.references :category, null: false, foreign_key: true
      t.references :payment_method, foreign_key: true
      t.boolean :enabled, null: false, default: true
      t.datetime :last_checked_at
      t.datetime :last_success_at
      t.text :last_error
      t.jsonb :activity, null: false, default: []
      t.timestamps
    end

    add_column :records, :external_ref, :string
    add_index :records, %i[household_id external_ref], unique: true, where: "external_ref IS NOT NULL"

    # The sync's own lines in a bill's history: added or filled in, and marked paid
    old_actions = "'created', 'updated', 'deleted', 'marked_paid', 'import_created', 'import_updated', 'import_undone', " \
      "'template_updated', 'reminders_restarted'"
    remove_check_constraint :record_events, "action IN (#{old_actions})", name: "record_events_action"
    add_check_constraint :record_events, "action IN (#{old_actions}, 'gas_synced', 'gas_paid')", name: "record_events_action"
  end
end
