# A ledger's 欣桃天然氣 用戶編號 (Ledger settings › Gas account). One per ledger, and one ledger per
# number. Every working day Utilities::ShintaoGas::Sync adds its new bills to `category` and marks
# them paid once the gas company shows them paid.
class GasAccount < UtilityAccount
  validates :customer_code, format: { with: /\A\d{10}\z/ }, uniqueness: true
end
