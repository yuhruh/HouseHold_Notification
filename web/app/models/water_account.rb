# A ledger's 台灣自來水 bills (Ledger settings › Water), read from 台水's 電子帳單 emails that
# whoever receives them forwards to the ledger's ForwardingInbox, the same address 台電's emails use
# (Utilities::TaiwanWater). The 水號 is set from the first bill email.
class WaterAccount < UtilityAccount
  include ForwardedBills
end
