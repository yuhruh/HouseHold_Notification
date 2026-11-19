require "test_helper"

class Supplies::PaidAmountTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    @day = @home.today - 2
    @asked = []
    @rate = BigDecimal("0.20612")
  end

  # JP¥1,196 for 2, bought the day before yesterday. The rate is the one in @rate (nil: none to be had)
  def resolve(**form)
    asked = @asked
    rate = @rate
    lookup = ->(from:, to:, on:) { asked << [ from, to, on ]; rate && Supplies::ExchangeRateLookup::Result.new(rate:, on:) }
    Supplies::PaidAmount.resolve({ quantity: 2, total_price: "1196", purchased_on: @day.iso8601, paid_currency: "JPY" }.merge(form), household: @home, lookup:)
  end

  def purchase(attributes)
    supply = @home.supplies.create!(name: "Face Wash", kind: "toiletries", unit: "piece", level: 0)
    supply.purchases.new(attributes.merge(household: @home, currency: "TWD", left_before: 0))
  end

  test "without a currency menu nothing changes; on the household's own currency the price is the amount" do
    plain = { quantity: 2, total_price: "169", purchased_on: @day.iso8601 }
    assert_equal plain, Supplies::PaidAmount.resolve(plain, household: @home)

    home = resolve(paid_currency: "TWD", total_price: "169", paid_by: "card", card_fee_percent: "1.5", home_total: "99")
    assert_equal "169", home[:total_price]
    assert_equal [ nil ] * 6, home.values_at(:paid_currency, :paid_total, :exchange_rate, :paid_by, :card_fee_percent, :card_fee_included)
    assert_not home.key?(:home_total)
    assert_empty @asked
  end

  test "by card, the amount with the 1.5% card fee is saved unless the one without it is chosen" do
    with_fee = resolve(paid_by: "card")
    assert_equal [ "JPY", 1196, 250, @rate, "card", BigDecimal("1.5"), true ],
                 with_fee.values_at(:paid_currency, :paid_total, :total_price, :exchange_rate, :paid_by, :card_fee_percent, :card_fee_included)
    assert_equal [ [ "JPY", "TWD", @day ] ], @asked, "the rate for the day it was bought"
    assert purchase(with_fee).valid?

    without = resolve(paid_by: "card", card_fee_percent: "1.5", card_fee_included: "0", home_total: "247", home_total_with_fee: "250")
    assert_equal [ 247, @rate, "card", BigDecimal("1.5"), false ], without.values_at(:total_price, :exchange_rate, :paid_by, :card_fee_percent, :card_fee_included)
  end

  test "a card fee of 3% changes the amount with the fee, and only that one" do
    assert_equal [ 254, BigDecimal("3") ], resolve(paid_by: "card", card_fee_percent: "3", card_fee_included: "1").values_at(:total_price, :card_fee_percent)
    assert_equal 247, resolve(paid_by: "card", card_fee_percent: "3", card_fee_included: "0")[:total_price]
    assert_equal 247, resolve(paid_by: "card", card_fee_percent: "0", card_fee_included: "1")[:total_price]

    over = purchase(resolve(paid_by: "card", card_fee_percent: "12", card_fee_included: "1"))
    assert_not over.valid?
    assert over.errors.of_kind?(:card_fee_percent, :less_than_or_equal_to)
  end

  test "in cash there is no card fee" do
    cash = resolve(paid_by: "cash", card_fee_percent: "1.5", card_fee_included: "1", home_total: "247")
    assert_equal [ 247, @rate, "cash", nil, nil ], cash.values_at(:total_price, :exchange_rate, :paid_by, :card_fee_percent, :card_fee_included)
  end

  test "an amount typed over the app's is what is saved, and then no rate is kept" do
    typed = resolve(paid_by: "card", card_fee_percent: "1.5", card_fee_included: "1", home_total: "247", home_total_with_fee: "252")
    assert_equal [ 252, nil, true ], typed.values_at(:total_price, :exchange_rate, :card_fee_included)
    same = resolve(paid_by: "card", card_fee_percent: "1.5", card_fee_included: "1", home_total_with_fee: "250")
    assert_equal [ 250, @rate ], same.values_at(:total_price, :exchange_rate), "the app's own figure isn't typed by hand"
    assert_equal [ 240, nil ], resolve(paid_by: "cash", home_total: "240").values_at(:total_price, :exchange_rate)
  end

  test "with no rate the amount has to be typed, and is saved as it is" do
    @rate = nil
    missing = purchase(resolve(paid_by: "card", card_fee_percent: "1.5", card_fee_included: "1"))
    assert_not missing.valid?
    assert_equal [ "目前查不到 JPY 的匯率。請輸入要記下的 NT$ 金額。" ], missing.errors.full_messages

    typed = resolve(paid_by: "card", home_total: "250")
    assert_equal [ 1196, 250, nil, "card", nil, nil ], typed.values_at(:paid_total, :total_price, :exchange_rate, :paid_by, :card_fee_percent, :card_fee_included)
    assert purchase(typed).valid?
  end

  test "a rate for a day that hasn't come isn't asked for; yen has no cents; an unknown currency is refused" do
    resolve(purchased_on: (@home.today + 1).iso8601)
    resolve(purchased_on: "soon")
    assert_empty @asked

    cents = purchase(resolve(total_price: "1196.5", paid_by: "cash"))
    assert_not cents.valid?
    assert cents.errors.of_kind?(:paid_total, :whole_number)
    assert purchase(resolve(paid_currency: "USD", total_price: "18.99", paid_by: "cash")).valid?

    unknown = purchase(resolve(paid_currency: "XXX"))
    assert_not unknown.valid?
    assert unknown.errors.of_kind?(:paid_currency, :inclusion)
  end

  test "the form opens on what was chosen last time: a card at 1.5% with the fee to begin with" do
    assert_equal({ paid_by: "card", card_fee_percent: BigDecimal("1.5"), card_fee_included: true }, Supplies::PaidAmount.defaults(@home))

    purchase(resolve(paid_by: "card", card_fee_percent: "3", card_fee_included: "0")).save!
    assert_equal({ paid_by: "card", card_fee_percent: BigDecimal("3"), card_fee_included: false }, Supplies::PaidAmount.defaults(@home))

    travel 1.minute
    @home.supplies.sole.purchases.new(resolve(paid_by: "cash").merge(household: @home, currency: "TWD", left_before: 0)).save!
    assert_equal({ paid_by: "cash", card_fee_percent: BigDecimal("3"), card_fee_included: false }, Supplies::PaidAmount.defaults(@home), "cash last time; the card's fee is remembered")
    assert_equal({ paid_by: "card", card_fee_percent: BigDecimal("1.5"), card_fee_included: true }, Supplies::PaidAmount.defaults(households(:parents)))
  end
end
