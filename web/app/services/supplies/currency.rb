module Supplies
  # The currencies a supply's price can be typed in: the household's own, and the ones people shop
  # in abroad. Each has the symbol it is written with and how many decimals it takes (yen, won and
  # dong have none). Bills and the Ledger keep their own short list (Household::CURRENCIES).
  class Currency
    Entry = Data.define(:code, :symbol, :decimals) do
      def whole? = decimals.zero?
      def step = whole? ? "1" : "0.01"
    end

    ALL = [
      [ "TWD", "NT$", 0 ], [ "JPY", "JP¥", 0 ], [ "USD", "US$", 2 ], [ "KRW", "₩", 0 ], [ "CNY", "CN¥", 2 ],
      [ "HKD", "HK$", 2 ], [ "EUR", "€", 2 ], [ "GBP", "£", 2 ], [ "THB", "฿", 2 ], [ "SGD", "S$", 2 ],
      [ "MYR", "RM", 2 ], [ "VND", "₫", 0 ], [ "AUD", "A$", 2 ], [ "CAD", "C$", 2 ]
    ].to_h { |code, symbol, decimals| [ code, Entry.new(code:, symbol:, decimals:) ] }.freeze
    CODES = ALL.keys.freeze

    def self.[](code) = ALL[code.to_s]
    def self.known?(code) = ALL.key?(code.to_s)

    # An amount in a currency, to the decimals that currency has
    def self.round(amount, code) = amount.round(self[code].decimals)

    # The currencies this household has paid in before, the latest first: they lead the menu
    def self.used_by(household)
      household.supply_purchases.where.not(paid_currency: nil).order(created_at: :desc).pluck(:paid_currency).uniq & CODES
    end
  end
end
