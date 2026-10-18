class CreateAuthHandoffs < ActiveRecord::Migration[8.1]
  def change
    # Carries tz/return_to across the Google round trip; only the id travels in the session (PRD §10)
    create_table :auth_handoffs, id: :uuid do |t|
      t.string :provider, null: false
      t.string :purpose, null: false, default: "sign_in"
      t.string :time_zone, null: false
      t.string :return_to
      t.string :nonce_digest
      t.references :user, foreign_key: { on_delete: :cascade }
      t.datetime :requested_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end
    add_index :auth_handoffs, :expires_at
  end
end
