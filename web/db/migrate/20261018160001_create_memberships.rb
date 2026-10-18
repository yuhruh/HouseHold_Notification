class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :household, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false

      t.timestamps
    end
    add_index :memberships, %i[household_id user_id], unique: true
    # At most one owner per household; OwnershipTransfer keeps exactly one (PRD data model)
    add_index :memberships, :household_id, unique: true, where: "role = 'owner'", name: "index_memberships_one_owner"
    add_check_constraint :memberships, "role IN ('owner', 'co_owner', 'viewer')", name: "memberships_role"
    add_foreign_key :users, :households, column: :last_household_id, on_delete: :nullify
  end
end
