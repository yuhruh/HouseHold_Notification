# Gmail confirms a new forwarding address with a link, not a code: the link is kept for the
# Electricity page's Confirm button. missing_mail_warned_for is the day 台電's email was expected
# when the owner was last told it hadn't come, so each missed bill is warned about once.
class AddForwardingLinkToUtilityAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :utility_accounts, :forwarding_link, :text
    add_column :utility_accounts, :missing_mail_warned_for, :date
  end
end
