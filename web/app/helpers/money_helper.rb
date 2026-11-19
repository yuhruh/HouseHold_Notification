# Money display (PRD → Data model): TWD with no decimals, USD with 2. A supply's price abroad is
# written with its own symbol and decimals (Supplies::Currency): JP¥1,196, €4.50
module MoneyHelper
  # exact: keep the decimals a price really has (a receipt's NT$98.5 unit price), no more
  def money(amount, currency, exact: false)
    return "–" if amount.nil?
    entry = Supplies::Currency[currency] || Supplies::Currency["TWD"]
    precision = entry.decimals.positive? || exact ? 2 : 0
    "#{entry.symbol}#{number_with_delimiter(number_with_precision(amount, precision:, strip_insignificant_zeros: exact))}"
  end
end
