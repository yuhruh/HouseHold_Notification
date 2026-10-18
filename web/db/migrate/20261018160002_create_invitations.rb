class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :household, null: false, foreign_key: true
      t.references :invited_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :email, null: false
      t.string :role, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at # null = never expires
      t.datetime :accepted_at
      t.datetime :declined_at
      t.datetime :revoked_at

      t.timestamps
    end
    add_index :invitations, :token_digest, unique: true
    add_index :invitations, :email
    # One open invitation per address and household (expiry can't go in an index predicate)
    add_index :invitations, %i[household_id email], unique: true,
      where: "accepted_at IS NULL AND declined_at IS NULL AND revoked_at IS NULL", name: "index_invitations_one_open"
    add_check_constraint :invitations, "role IN ('co_owner', 'viewer')", name: "invitations_role"
  end
end
