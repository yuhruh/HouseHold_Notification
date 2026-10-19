class CreateRecordEvents < ActiveRecord::Migration[8.1]
  def change
    # Per-record activity log (PRD → Data model). record_id has no FK: events outlive the record.
    # The PRD's `changes` column is `diff` here (`changes` is an Active Record method).
    create_table :record_events do |t|
      t.references :household, null: false, foreign_key: true, index: false
      t.bigint :record_id, null: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.bigint :import_batch_id
      t.string :action, null: false
      t.jsonb :diff, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :record_events, %i[household_id created_at]
    add_index :record_events, %i[record_id created_at]
    add_check_constraint :record_events,
      "action IN ('created', 'updated', 'deleted', 'marked_paid', 'import_created', 'import_updated', 'import_undone')",
      name: "record_events_action"
  end
end
