module Supplies
  # A price typed in another currency (something bought abroad) becomes the amount in the
  # household's currency that the purchase is saved with. total_price always means that home amount,
  # so prices compare across stores and countries, and the Ledger expense is in one currency; the
  # foreign price is kept beside it.
  #
  # From the form: the currency menu (paid_currency), the price box (total_price, in that currency),
  # Paid with (paid_by: card or cash), Card fee (card_fee_percent), which amount to save
  # (card_fee_included) and the two home-currency boxes (home_total, and home_total_with_fee for a
  # card). The rate is the one for the day of the purchase. By card with the fee:
  # price × rate × (1 + fee%); otherwise price × rate.
  #
  # The browser's figures are only a preview: the amount is worked out again here, and a box is
  # "typed by hand" (it wins, and no rate is kept) only when it differs from that. With no rate the
  # form has a single box (home_total) and neither choice is sent: what was typed is saved as it is.
  class PaidAmount
    FORM_ONLY = %i[home_total home_total_with_fee].freeze
    KEYS = %i[paid_currency paid_by card_fee_percent card_fee_included home_total home_total_with_fee].freeze
    CLEARED = { paid_currency: nil, paid_total: nil, exchange_rate: nil, paid_by: nil, card_fee_percent: nil, card_fee_included: nil }.freeze
    PAID_BY = %w[card cash].freeze
    DEFAULT_CARD_FEE = BigDecimal("1.5")
    MAX_CARD_FEE = 10

    # → the attributes to save a purchase or an old price with
    def self.resolve(attributes, household:, lookup: ExchangeRateLookup)
      attributes = attributes.to_h.symbolize_keys
      return attributes unless attributes.key?(:paid_currency)

      new(attributes, household:, lookup:).resolve
    end

    # What Paid with, Card fee and the amount chosen open on: what this household did last time
    # (the first time a card, 1.5%, with the fee)
    def self.defaults(household)
      abroad = household.supply_purchases.where.not(paid_currency: nil).order(created_at: :desc)
      last = abroad.first
      card = abroad.where(paid_by: "card").where.not(card_fee_percent: nil).first
      { paid_by: last&.paid_by || "card", card_fee_percent: card&.card_fee_percent || DEFAULT_CARD_FEE, card_fee_included: card&.card_fee_included != false }
    end

    def initialize(attributes, household:, lookup:)
      @form = attributes.slice(*KEYS)
      @rest = attributes.except(*KEYS)
      @household = household
      @lookup = lookup
    end

    def resolve
      home = @household.default_currency
      code = @form[:paid_currency].to_s
      return @rest.merge(CLEARED) if code.blank? || code == home
      # Not a currency on the list: kept as typed, and the purchase says so when it is checked
      return @rest.merge(CLEARED, paid_currency: code, paid_total: @rest[:total_price]) unless Currency.known?(code)

      paid = decimal(@rest[:total_price])
      card = @form[:paid_by] != "cash"
      fee = (decimal(@form[:card_fee_percent]) || DEFAULT_CARD_FEE if card)
      # No rate on the form: one box, and the amount typed in it is the amount
      bare = card && @form[:card_fee_included].nil? && @form[:home_total].present?
      included = (ActiveModel::Type::Boolean.new.cast(@form[:card_fee_included]) != false if card && !bare)
      rate = rate_for(code, home)
      worked_out = (Currency.round(paid * rate * (included ? 1 + fee / 100 : 1), home) if rate && paid && (fee.nil? || fee.between?(0, MAX_CARD_FEE)))
      typed = decimal(included ? @form[:home_total_with_fee] : @form[:home_total])
      by_hand = typed && typed != worked_out

      @rest.merge(paid_currency: code, paid_total: paid, total_price: typed || worked_out, exchange_rate: (rate unless by_hand || worked_out.nil?),
                  paid_by: card ? "card" : "cash", card_fee_percent: (fee unless bare), card_fee_included: included,
                  **@form.slice(*FORM_ONLY))
    end

    private

    # The rate for the day it was bought; none for a day that hasn't come or isn't a date
    def rate_for(code, home)
      on = bought_on
      @lookup.call(from: code, to: home, on:)&.rate if on && on <= @household.today
    end

    def bought_on
      on = @rest[:purchased_on]
      on.is_a?(Date) ? on : Date.iso8601(on.to_s)
    rescue Date::Error
      nil
    end

    def decimal(value) = (BigDecimal(value.to_s.strip) if value.to_s.strip.match?(/\A\d+(\.\d+)?\z/))
  end
end
