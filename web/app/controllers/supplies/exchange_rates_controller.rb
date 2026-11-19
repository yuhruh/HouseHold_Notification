# The rate a price typed in another currency is turned into the household's own with, for the day it
# was bought: the price field asks as the currency, the price or the date changes
# (paid_currency_controller). Saving works the amount out again (Supplies::PaidAmount).
#
# { rate: "0.20612", on: "2026-11-16" } (on: the day the rate is for), or { rate: null } when there
# is none to be had; the form then asks for the amount itself.
class Supplies::ExchangeRatesController < ApplicationController
  include HouseholdScoped
  rate_limit to: 120, within: 1.minute, by: -> { Current.household.id }, with: -> { render json: { rate: nil } }

  def show
    authorize Supply, :create?
    found = Supplies::ExchangeRateLookup.call(from: params[:from].to_s, to: Current.household.default_currency, on: bought_on) if bought_on
    render json: found ? { rate: found.rate.to_s("F"), on: found.on.iso8601 } : { rate: nil }
  end

  private

  # Not a day that hasn't come: a purchase can't be dated ahead
  def bought_on
    @bought_on ||= Date.iso8601(params[:on].to_s).then { it if it <= Current.household.today }
  rescue Date::Error
    nil
  end
end
