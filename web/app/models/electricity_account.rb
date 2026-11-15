# A ledger's 台電 bills (Ledger settings › Electricity), read from 台電's 電子帳單 emails that
# whoever receives them forwards to the ledger's ForwardingInbox (Utilities::Taipower). The 電號
# is set from the first bill email.
class ElectricityAccount < UtilityAccount
  include ForwardedBills
end
