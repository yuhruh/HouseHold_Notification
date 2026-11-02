# Restoring a ledger from its Drive backup: what a fresh connection found, and how a restore is going
class AddRestoreToDriveBackups < ActiveRecord::Migration[8.1]
  def change
    change_table :drive_backups, bulk: true do |t|
      t.jsonb :found_backups, null: false, default: []
      t.string :restore_state
      t.integer :restore_bills, null: false, default: 0
      t.integer :restore_total, null: false, default: 0
      t.integer :restore_done, null: false, default: 0
      t.integer :restore_unmatched, null: false, default: 0
      t.check_constraint "restore_state IN ('running', 'finished', 'failed')", name: "drive_backups_restore_state"
    end
  end
end
