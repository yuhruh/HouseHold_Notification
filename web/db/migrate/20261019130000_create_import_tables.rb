class CreateImportTables < ActiveRecord::Migration[8.1]
  def change
    create_table :import_batches do |t|
      t.references :household, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :filename, null: false
      t.integer :row_count, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :unchanged_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.datetime :undone_at

      t.timestamps
    end

    create_table :import_batch_changes do |t|
      t.references :import_batch, null: false, foreign_key: true
      t.bigint :record_id, null: false
      t.string :action, null: false
      t.jsonb :before
      t.jsonb :after, null: false, default: {}

      t.timestamps
    end
    add_check_constraint :import_batch_changes, "action IN ('created', 'updated')", name: "import_batch_changes_action"

    # Every sheet ID ever used in the household (PRD → Data model)
    create_table :import_keys do |t|
      t.references :household, null: false, foreign_key: true, index: false
      t.string :key, null: false
      t.references :record, foreign_key: { on_delete: :nullify }
      t.references :import_batch, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "active"
      t.string :source_key
      t.string :retired_digest
      t.datetime :pasted_back_at
      t.datetime :created_at, null: false
    end
    add_index :import_keys, %i[household_id key], unique: true
    add_check_constraint :import_keys, "status IN ('active', 'retired')", name: "import_keys_status"

    create_table :import_previews, id: :uuid do |t|
      t.references :household, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :cascade }
      t.string :filename, null: false
      t.string :csv_sha256, null: false
      t.jsonb :rows, null: false, default: []
      t.jsonb :choices, null: false, default: {}
      t.jsonb :record_versions, null: false, default: {}
      t.datetime :expires_at, null: false
      t.datetime :committed_at

      t.timestamps
    end

    add_reference :records, :import_batch, foreign_key: { on_delete: :nullify }
  end
end
