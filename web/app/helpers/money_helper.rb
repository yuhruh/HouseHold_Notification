# Money display (PRD → Data model): TWD with no decimals, USD with 2
module MoneyHelper
  def money(amount, currency)
    return "–" if amount.nil?
    precision = currency == "USD" ? 2 : 0
    "#{currency == 'USD' ? 'US$' : 'NT$'}#{number_with_delimiter(number_with_precision(amount, precision:))}"
  end
end
