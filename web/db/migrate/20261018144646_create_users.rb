class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      # Only a confirmed address lives here; a pending one sits in unconfirmed_email (PRD §10)
      t.string :email_address
      t.string :unconfirmed_email
      t.datetime :email_confirmed_at
      t.string :password_digest
      t.string :display_name
      t.string :locale
      t.string :time_zone, null: false, default: "Asia/Taipei"
      t.integer :reminder_hour, null: false, default: 8
      t.boolean :push_show_amounts, null: false, default: true
      t.bigint :last_household_id

      t.timestamps
    end
    add_index :users, :email_address, unique: true, where: "email_address IS NOT NULL"
    add_index :users, :unconfirmed_email
  end
end
