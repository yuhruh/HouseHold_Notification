# Money display (PRD → Data model): TWD with no decimals, USD with 2
module MoneyHelper
  # exact: keep the decimals a price really has (a receipt's NT$98.5 unit price), no more
  def money(amount, currency, exact: false)
    return "–" if amount.nil?
    precision = currency == "USD" || exact ? 2 : 0
    "#{currency == 'USD' ? 'US$' : 'NT$'}#{number_with_delimiter(number_with_precision(amount, precision:, strip_insignificant_zeros: exact))}"
  end
end
