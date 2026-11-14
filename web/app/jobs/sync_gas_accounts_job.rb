# Working days at 11:30 Taipei (欣桃天然氣 updates at 11:00): each ledger's gas account adds its new
# bills and marks paid ones (Utilities::ShintaoGas::Sync). With an id it checks that one now (Check
# now). A ledger whose check fails keeps the reason on its account; the others still run.
class SyncGasAccountsJob < ApplicationJob
  queue_as :default

  def perform(gas_account_id = nil)
    accounts = gas_account_id ? GasAccount.where(id: gas_account_id) : GasAccount.enabled
    accounts.includes(household: :owner).find_each do |account|
      Utilities::ShintaoGas::Sync.call(account)
    rescue StandardError => e
      Rails.error.report(e, context: { gas_account_id: account.id })
    end
  end
end
