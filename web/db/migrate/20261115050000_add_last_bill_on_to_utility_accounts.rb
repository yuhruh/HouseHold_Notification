# The 收費日 (issue date) of the latest 台電 bill an email brought in, so the Electricity page and
# the missing-mail warning expect the next bill 2 months after it rather than after whichever
# email came last (the paid notice comes ~2 weeks later) or the day Electricity was turned on.
class AddLastBillOnToUtilityAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :utility_accounts, :last_bill_on, :date
  end
end
