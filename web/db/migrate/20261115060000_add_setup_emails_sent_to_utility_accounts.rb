# When the owner last sent each forwarder the setup email (Electricity › Set up forwarding), as
# {"email" => ISO time}: the page shows it, and a resend within a minute is refused.
class AddSetupEmailsSentToUtilityAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :utility_accounts, :setup_emails_sent, :jsonb, default: {}, null: false
  end
end
