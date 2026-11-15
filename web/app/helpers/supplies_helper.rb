module SuppliesHelper
  STATUS_ORDER = %i[out buy_now buy_soon expiring ok not_enough_data].freeze
  # Badge colours: red to buy, orange expiring, green fine, grey still learning (each also has a word)
  BADGE = {
    out: "border-red-800 bg-red-100 text-red-800", buy_now: "border-red-800 bg-red-100 text-red-800",
    buy_soon: "border-red-800 bg-red-50 text-red-800", expiring: "border-orange-800 bg-orange-100 text-orange-800",
    ok: "border-green-800 bg-green-100 text-green-800", not_enough_data: "border-gray-700 bg-gray-100 text-gray-700"
  }.freeze
  BAR = { out: "bg-red-600", buy_now: "bg-red-600", buy_soon: "bg-red-500", expiring: "bg-orange-500", ok: "bg-green-600", not_enough_data: "bg-gray-400" }.freeze
  CARD = { out: "bg-red-50", buy_now: "bg-red-50", buy_soon: "bg-red-50", expiring: "bg-orange-50", ok: "bg-white", not_enough_data: "bg-white" }.freeze

  # "3 rolls", "1 bottle" ("~2 rolls" when it's an estimate between counts)
  def supply_count(supply, count, estimate: false)
    text = t("supplies.units.#{supply.unit}", count:)
    estimate && count.positive? ? "~#{text}" : text
  end

  def supply_left(supply, forecast) = supply_count(supply, forecast.on_hand_rounded, estimate: forecast.estimated?)

  def supply_badge(status)
    tag.span(t("supplies.status.#{status}"), class: "whitespace-nowrap rounded-full border-[1.5px] px-2 py-0.5 text-[11px] font-bold #{BADGE.fetch(status)}")
  end

  # Price per unit, worked out from the total: 1 decimal, none from 100 up
  def supply_unit_price(purchase)
    price = purchase.unit_price
    precision = price >= 100 || price == price.round ? 0 : 1
    prefix = purchase.currency == "USD" ? "US$" : "NT$"
    precision = 2 if purchase.currency == "USD" && price < 100
    "#{prefix}#{number_with_delimiter(number_with_precision(price, precision:))}"
  end

  # "NT$289 for 12 · NT$24.1/roll"
  def supply_price_line(purchase)
    t("supplies.price_line", total: money(purchase.total_price, purchase.currency), quantity: purchase.quantity,
      unit_price: supply_unit_price(purchase), unit: t("supplies.units.#{purchase.supply.unit}_one"))
  end

  # The one-line summary under a list item: the run-out and buy-by dates, expiry, or what to do next
  def supply_line(supply, forecast)
    if (expiring = forecast.expiring) && %i[expiring ok].include?(forecast.status)
      t("supplies.line.expiring", left: supply_count(supply, expiring.left_at_expiry), date: l(expiring.expires_on, format: :short))
    elsif forecast.out? && forecast.enough_data?
      t("supplies.line.out")
    elsif forecast.run_out_on && forecast.needs_buying?
      t("supplies.line.runs_out_buy_by", date: l(forecast.run_out_on, format: :short), buy_by: l([ forecast.buy_by, forecast.today ].max, format: :short))
    elsif forecast.run_out_on
      t("supplies.line.runs_out", date: l(forecast.run_out_on, format: :short))
    elsif forecast.at_alert_level?
      t("supplies.line.at_alert_level", count: supply.alert_when_left)
    else
      t("supplies.line.not_enough_data")
    end
  end

  def supply_line_class(forecast)
    case forecast.status
    when :out, :buy_now, :buy_soon then "text-red-800"
    when :expiring then "text-orange-800"
    when :not_enough_data then "text-gray-600"
    else "text-gray-700"
    end
  end

  # Opens in a dialog on a computer, as its own page on a phone (modal_link_controller)
  def modal_link_data = { controller: "modal-link", action: "click->modal-link#route" }

  # This page was loaded into the layout's "modal" frame (a dialog on a computer)
  def in_modal? = turbo_frame_request_id == "modal"

  # Cancel: closes the dialog, or goes back on its own page
  def modal_cancel(path)
    return cancel_link(path) unless in_modal?
    tag.button(type: "button", data: { action: "modal#close" }, class: "btn-press inline-flex cursor-pointer items-center gap-1.5 rounded-xl bg-amber-100 px-3.5 py-2 font-medium text-amber-900") do
      safe_join([ tag.span("✕", "aria-hidden": "true"), tag.span(t("records.form.cancel")) ])
    end
  end

  # "about 3 a week", or "about 1 every 5 days" for slower ones
  def supply_rate(supply, forecast)
    per_week = forecast.rate * 7
    if per_week >= 1
      t("supplies.show.rate_week", amount: supply_count(supply, per_week.round))
    else
      t("supplies.show.rate_days", amount: supply_count(supply, 1), days: (1 / forecast.rate).round)
    end
  end

  # A History line: "+12 · NT$289 · Costco" or "Counted: 4 rolls"
  def supply_history_line(supply, event)
    if event.is_a?(SupplyPurchase)
      safe_join([ "+#{supply_count(supply, event.quantity)}", money(event.total_price, event.currency), event.store.presence ].compact, " · ")
    else
      t("supplies.show.counted_line", left: supply_count(supply, event.level))
    end
  end

  def supply_kind(kind) = t("supplies.kinds.#{kind}")

  # Total spent on an item, since its first purchase, and about how much a month
  def supply_spending(supply)
    purchases = supply.purchases.to_a
    return nil if purchases.empty?
    first = purchases.map(&:purchased_on).min
    total = purchases.sum(&:total_price)
    months = [ (supply.household.today - first).to_f / 30.4, 1 ].max
    currency = purchases.first.currency
    t("supplies.show.total_spent", total: money(total, currency), since: l(first, format: :supply_month), monthly: money((total / months).round, currency))
  end
end
