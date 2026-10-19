module Spend
  # Splits a paid amount evenly across the months of a billing period (PRD → Business rules):
  # each month gets amount ÷ months rounded down (TWD to dollars, USD to cents), and the remainder
  # goes to the last month, so the parts always add up to the amount.
  module Allocator
    Part = Data.define(:year, :month, :amount)

    module_function

    def call(period, amount, currency)
      months = period.month_count
      unit = currency == "USD" ? BigDecimal("0.01") : BigDecimal("1")
      share = ((amount.to_d / months) / unit).floor * unit
      start = period.start_year * 12 + period.start_month - 1
      (0...months).map do |i|
        index = start + i
        value = i == months - 1 ? amount.to_d - share * (months - 1) : share
        Part.new(year: index / 12, month: index % 12 + 1, amount: value)
      end
    end
  end
end
