class CreateSecurityEvents < ActiveRecord::Migration[8.1]
  def change
    # Audit trail. Plain id columns (no foreign keys) so entries outlive deleted users and households.
    create_table :security_events do |t|
      t.bigint :user_id
      t.bigint :actor_id
      t.bigint :household_id
      t.string :kind, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :security_events, %i[household_id created_at]
    add_index :security_events, %i[user_id created_at]
  end
end
