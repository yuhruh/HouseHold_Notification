# Something bought abroad: the price as the receipt prints it (JP¥1,196) is kept beside the amount in
# the household's currency, which total_price goes on meaning, so every comparison, total and the
# Ledger stay in one currency.
#   paid_currency, paid_total  the foreign price; both empty for a purchase in the household's currency
#   exchange_rate              the rate used; empty when the home amount was typed by hand
#   paid_by                    "card" or "cash"
#   card_fee_percent           the card's foreign transaction fee, for a card purchase
#   card_fee_included          which of the two amounts was saved: with the fee, or without it
# exchange_rates keeps each day's rate once it has been asked for: public facts, shared by every
# household. rated_on is the day asked about, published_on the day the service answered for
class SuppliesPaidInAnotherCurrency < ActiveRecord::Migration[8.1]
  def change
    %i[supply_purchases supply_prices].each do |table|
      add_column table, :paid_currency, :string
      add_column table, :paid_total, :decimal, precision: 12, scale: 2
      add_column table, :exchange_rate, :decimal, precision: 18, scale: 8
      add_column table, :paid_by, :string
      add_column table, :card_fee_percent, :decimal, precision: 4, scale: 2
      add_column table, :card_fee_included, :boolean
      add_check_constraint table, "(paid_currency IS NULL) = (paid_total IS NULL)", name: "#{table}_paid_currency_and_total"
      add_check_constraint table, "paid_by IN ('card', 'cash')", name: "#{table}_paid_by_known"
    end

    create_table :exchange_rates do |t|
      t.string :base, null: false
      t.string :quote, null: false
      t.date :rated_on, null: false
      t.decimal :rate, precision: 18, scale: 8, null: false
      t.date :published_on, null: false
      t.datetime :fetched_at, null: false
      t.index %i[base quote rated_on], unique: true
    end
  end
end
