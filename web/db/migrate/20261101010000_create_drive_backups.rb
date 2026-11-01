# Google Drive backup: one connection per household, made by its owner. drive_backup_files remembers
# which photos are already in Drive, so each run only uploads new ones.
class CreateDriveBackups < ActiveRecord::Migration[8.1]
  def change
    create_table :drive_backups do |t|
      t.references :household, null: false, foreign_key: true, index: { unique: true }
      t.references :connected_by, null: false, foreign_key: { to_table: :users }
      t.string :google_email, null: false
      t.text :refresh_token, null: false
      t.string :folder_id
      t.string :csv_file_id
      t.jsonb :folders, null: false, default: {}
      t.datetime :running_since
      t.datetime :last_backup_at
      t.integer :bills_count, null: false, default: 0
      t.integer :photos_count, null: false, default: 0
      t.string :problem
      t.timestamps
      t.check_constraint "problem IN ('reconnect', 'storage_full', 'failed')", name: "drive_backups_problem"
    end

    create_table :drive_backup_files do |t|
      t.references :drive_backup, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :blob_id, null: false
      t.string :drive_file_id, null: false
      t.timestamps
      t.index %i[drive_backup_id blob_id], unique: true
    end
  end
end
