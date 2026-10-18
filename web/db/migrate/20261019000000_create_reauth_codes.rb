class CreateReauthCodes < ActiveRecord::Migration[8.1]
  def change
    # Emailed 6-digit codes for Google-only re-authentication (PRD §15, M0 check X1)
    create_table :reauth_codes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :purpose, null: false
      t.string :code_digest, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end
    add_column :sessions, :reauthenticated_at, :datetime
  end
end
