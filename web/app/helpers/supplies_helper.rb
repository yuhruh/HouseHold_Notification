module SuppliesHelper
  STATUS_ORDER = %i[out buy_now buy_soon expiring ok not_enough_data].freeze
  # Each group has its own colour, soft in dark mode and told apart by lightness as well as hue: red
  # out or buy now, amber buy within 7 days, violet expiring, grey not enough data yet. Fixed hex values
  # with dark: variants, so dark.css's mirrored palette (which turns red-100 and amber-100 into two
  # loud, look-alike browns) doesn't touch them
  TONE = {
    now: { card: "bg-[#fee2e2] dark:bg-[#4b1d1b]", ink: "text-[#991b1b] dark:text-[#ffb4b0]", line: "border-[#991b1b] dark:border-[#ffb4b0]" },
    soon: { card: "bg-[#fef3c7] dark:bg-[#443617]", ink: "text-[#92400e] dark:text-[#f2d995]", line: "border-[#92400e] dark:border-[#f2d995]" },
    expiring: { card: "bg-[#ede9fe] dark:bg-[#302749]", ink: "text-[#5b21b6] dark:text-[#d1c5fa]", line: "border-[#5b21b6] dark:border-[#d1c5fa]" },
    no_data: { card: "bg-[#f3f4f6] dark:bg-[#27292d]", ink: "text-[#374151] dark:text-[#cdd1d8]", line: "border-[#374151] dark:border-[#cdd1d8]" },
    ok: { card: "bg-white dark:bg-[#282228]", ink: "text-[#166534] dark:text-[#9fdcb0]", line: "border-[#166534] dark:border-[#9fdcb0]" }
  }.freeze
  TONE_OF = { out: :now, buy_now: :now, buy_soon: :soon, expiring: :expiring, not_enough_data: :no_data, ok: :ok }.freeze
  BAR = { out: "bg-red-600", buy_now: "bg-red-600", buy_soon: "bg-amber-500", expiring: "bg-violet-500", ok: "bg-green-600", not_enough_data: "bg-gray-400" }.freeze

  # Nothing left as far as the app knows (the count, or the estimate shown, is 0): −1 is off and a
  # pop-up says to restock. A purchase or "I have N left" turns −1 back on
  def supply_used_up?(forecast) = forecast.on_hand_rounded.zero?

  def supply_tone(status, part) = TONE.fetch(TONE_OF.fetch(status)).fetch(part)

  # "3 rolls", "1 bottle" ("~2 rolls" when it's an estimate between counts)
  def supply_count(supply, count, estimate: false)
    text = t("supplies.units.#{supply.unit}", count:)
    estimate && count.positive? ? "~#{text}" : text
  end

  def supply_left(supply, forecast) = supply_count(supply, forecast.on_hand_rounded, estimate: forecast.estimated?)

  # The Favorites tab's count: its own element (hidden at 0), so starring an item updates it in place
  def supply_favorites_badge(count)
    tag.span(count, id: "supplies_favorites_count", class: "rounded-full bg-amber-200 px-1.5 text-[11px] font-bold text-amber-900 sm:text-xs #{'hidden' if count.zero?}")
  end

  # The All list's Left column: just the number over the bar ("9", "~2" for an estimate), like the Total
  # at the bar's other end; a screen reader still gets the unit ("9 bottles")
  def supply_left_number(supply, forecast)
    count = forecast.on_hand_rounded
    number = forecast.estimated? && count.positive? ? "~#{number_with_delimiter(count)}" : number_with_delimiter(count)
    safe_join([ tag.span(number, aria: { hidden: true }), tag.span(supply_left(supply, forecast), class: "sr-only") ])
  end

  # "Total: 25 bottles" over the right end of the stock bar (the bar's full length); in the lists just
  # "Total: 25", the unit is right beside it. Nothing for an empty item nobody has bought yet
  def supply_total(supply, forecast, unit: true)
    total = forecast.full_stock
    return unless total.positive?

    tag.span(t("supplies.total", total: unit ? supply_count(supply, total) : number_with_delimiter(total)), class: "whitespace-nowrap text-gray-600 #{unit ? 'text-sm' : 'text-xs'} font-semibold")
  end

  def supply_badge(status)
    tag.span(t("supplies.status.#{status}"), class: "whitespace-nowrap rounded-full border-[1.5px] px-2 py-0.5 text-[11px] font-bold #{supply_tone(status, :card)} #{supply_tone(status, :ink)} #{supply_tone(status, :line)}")
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

  def supply_line_class(forecast) = forecast.status == :ok ? "text-gray-700" : supply_tone(forecast.status, :ink)

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
