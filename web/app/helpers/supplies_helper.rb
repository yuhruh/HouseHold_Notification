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

  # What the take-one-off button says, in the item's own unit: "Used 1 bottle", "Used 1 roll"
  def supply_used_one(supply) = t("supplies.actions.used_one", amount: supply_count(supply, 1))

  # What is left of each brand of an item (Supplies::Brands), worked out once per item on a page
  def supply_brands(supply, forecast) = (@supply_brands ||= {})[supply.id] ||= supply.brands(forecast)

  def supply_brand_name(brand) = brand.name || t("supplies.brands.unnamed")

  # On a To Buy or Favorites card (not an All row, which has only the category under the
  # name), under an item with several brands in stock: "2 Lux Shampoo 750ml · 1 Pantene Shampoo 700ml", the
  # brand bought last first. They add up to the number left shown beside it
  def supply_brand_split(supply, forecast)
    brands = supply_brands(supply, forecast)
    return unless brands.several?

    parts = brands.list.select { it.left.positive? }.reverse.map do |brand|
      safe_join([ tag.strong(number_with_delimiter(brand.left), class: "text-gray-900"), supply_brand_name(brand), supply_brand_inside(supply, brand) ].compact, " ")
    end
    tag.p(safe_join(parts, " · "), class: "text-xs text-gray-600 [overflow-wrap:anywhere]") if parts.any?
  end

  # A brand in the −1 menu and on the item page: its name, and on the one to use first why it is
  # first: "Expires first" (or "Expired") when its stock has an expiry date, else "Oldest"
  def supply_brand_title(brand)
    first = if !brand.first then nil
    elsif brand.expires_on.nil? then [ "oldest", "bg-sky-100 text-sky-900" ]
    elsif brand.expires_on < Current.household.today then [ "expired", "bg-red-100 text-red-900" ]
    else [ "expires_first", "bg-amber-100 text-amber-900" ]
    end
    first &&= tag.span(t("supplies.brands.#{first.first}"), class: "ml-1 rounded-full px-1.5 py-px text-[11px] font-bold whitespace-nowrap #{first.last}")
    tag.span(safe_join([ supply_brand_name(brand), first ].compact, " "), class: "block text-sm font-bold [overflow-wrap:anywhere]")
  end

  # "Expires Mar 12, 2027 · Bought Sep 28 · Coupang" (and the price per unit on the item page): the
  # purchase its stock to use first is from. The expiry date only when that purchase has one
  def supply_brand_source(brand, price: false, store: true)
    purchase = brand.purchase
    return unless purchase
    expiry = purchase.expires_on
    safe_join([ (t("supplies.brands.#{expiry < Current.household.today ? "expired_on" : "expires_on"}", date: l(expiry, format: :supply_date)) if expiry),
                t("supplies.brands.bought", date: l(purchase.purchased_on, format: :short)), (purchase.store.presence if store),
                (supply_unit_prices(purchase) if price) ].compact, " · ")
  end

  # Each person's star colour (Supplies::Starrers::COLORS): the fill and text of their button and tag,
  # the star itself and the tag's outline
  STAR_TONE = {
    "amber" => { fill: "bg-amber-100", ink: "text-amber-900", icon: "text-amber-700", line: "border-amber-700" },
    "teal" => { fill: "bg-teal-100", ink: "text-teal-900", icon: "text-teal-700", line: "border-teal-700" },
    "violet" => { fill: "bg-violet-100", ink: "text-violet-900", icon: "text-violet-700", line: "border-violet-700" },
    "rose" => { fill: "bg-rose-100", ink: "text-rose-900", icon: "text-rose-700", line: "border-rose-700" },
    "sky" => { fill: "bg-sky-100", ink: "text-sky-900", icon: "text-sky-700", line: "border-sky-700" },
    "lime" => { fill: "bg-lime-100", ink: "text-lime-900", icon: "text-lime-700", line: "border-lime-700" }
  }.freeze
  STAR_PATH = "M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8L3.5 9.7l5.9-.9z".freeze

  # Who can star in this household, with their colours; one lookup for the whole page
  def supply_starrers = @supply_starrers ||= Supplies::Starrers.new(Current.household)

  # Owners and co-owners star an item in use; a viewer, or anyone on an archived item, only sees the stars
  def supply_can_star?(supply) = supply.archived_at.nil? && policy(supply).update? && supply_starrers.person(Current.user).present?

  def supply_star_icon(size, filled: true, tone: nil)
    tag.svg(tag.path(d: STAR_PATH), class: "#{size} shrink-0 #{tone}", viewBox: "0 0 24 24", fill: (filled ? "currentColor" : "none"),
            stroke: "currentColor", "stroke-width": "2", "stroke-linejoin": "round", "aria-hidden": "true")
  end

  # Someone's star on an item: a small tag in their colour with their initial, or their name (the item page)
  def supply_star_tag(person, name: false)
    tone = STAR_TONE.fetch(person.color)
    said = t("supplies.favorite.by", name: person.name)
    text = name ? [ tag.span(person.name) ] : [ tag.span(person.initial, aria: { hidden: true }), tag.span(said, class: "sr-only") ]
    tag.span(safe_join([ supply_star_icon("h-3 w-3", tone: tone[:icon]), *text ]), title: (said unless name),
             class: "inline-flex h-6 shrink-0 items-center gap-0.5 rounded-full border-[1.5px] pl-1.5 pr-2 text-xs leading-none font-extrabold #{tone[:fill]} #{tone[:ink]} #{tone[:line]}")
  end

  # The other people's stars on an item, beside your own star button; all of them where there is no
  # button (a viewer, an archived item)
  def supply_star_tags(supply, name: false)
    people = supply_starrers.of(supply)
    people = people.reject { it.user == Current.user } if supply_can_star?(supply)
    safe_join(people.map { supply_star_tag(it, name:) }, " ")
  end

  # The item page, under the Favorite button: "Also starred by ★ Sam" ("Starred by" when your own star isn't on it)
  def supply_starred_by(supply)
    tags = supply_star_tags(supply, name: true)
    return if tags.blank?

    mine = supply_can_star?(supply) && supply_starrers.starred_by?(supply, Current.user)
    tag.p(safe_join([ tag.span(t(mine ? "supplies.favorite.also_by" : "supplies.favorite.starred_by")), tags ], " "),
          class: "flex flex-wrap items-center justify-end gap-1.5 text-sm text-gray-700")
  end

  # A "Starred by" chip on Favorites, one at a time: Everyone, or a person with a star in their colour
  # (the row is also the key to the colours). The count is its own element, so a star updates it in place
  def supply_star_chip(label, path, count:, count_id:, chosen:, person: nil)
    tone = STAR_TONE.fetch(person.color) if person
    look = if !chosen then "border-(--card-line) bg-white font-semibold"
    elsif tone then "#{tone[:line]} #{tone[:fill]} #{tone[:ink]} font-extrabold"
    else "border-blue-700 bg-blue-100 font-bold text-blue-900"
    end
    link_to path, class: "inline-flex min-h-9 items-center gap-1.5 rounded-full border-2 px-3 text-sm #{look}", "aria-current": (chosen ? "true" : nil) do
      safe_join([ (supply_star_icon("h-4 w-4", tone: tone[:icon]) if tone), tag.span(label), tag.span(count, id: count_id, class: "text-xs font-extrabold") ].compact, " ")
    end
  end

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
  def supply_unit_price(purchase) = supply_price(purchase.unit_price, purchase.currency)

  def supply_price(price, currency)
    precision = price >= 100 || price == price.round ? 0 : 1
    prefix = (Supplies::Currency[currency] || Supplies::Currency["TWD"]).symbol
    precision = 2 if currency == "USD" && price < 100
    "#{prefix}#{number_with_delimiter(number_with_precision(price, precision:))}"
  end

  # "NT$24.1/roll"; a purchase that says what was in its pack adds the price of one: "NT$60/pack ·
  # NT$15/piece" (each brand its own)
  def supply_unit_prices(purchase) = supply_unit_price_parts(purchase).join(" · ")

  def supply_unit_price_parts(purchase)
    prices = [ t("supplies.unit_price", price: supply_unit_price(purchase), unit: t("supplies.units.#{purchase.supply.unit}_one")) ]
    if purchase.packed?
      prices << t("supplies.unit_price", price: supply_price(purchase.piece_price, purchase.currency), unit: t("supplies.units.#{purchase.pack_unit}_one"))
    end
    prices
  end

  # What's inside the packs left: "44 pieces", each brand's packs times its own size (Supply#pack_sizes).
  # Nil when a brand in stock has no size, or the brands hold different things (rolls and pieces)
  def supply_inside(supply, forecast)
    sizes = supply.pack_sizes
    return if sizes.empty? || !supply.in_packs?

    stocked = supply_brands(supply, forecast).list.select { it.left.positive? }
    return if stocked.empty? || stocked.any? { !sizes.key?(it.key) }

    sizes = stocked.map { sizes[it.key] }
    return unless sizes.map(&:last).uniq.one?

    t("supplies.units.#{sizes.first.last}", count: stocked.zip(sizes).sum { |brand, (size, _)| brand.left * size })
  end

  # One brand's packs left in pieces, on the brand line: "(12 pieces)", or nil when it has no size
  def supply_brand_inside(supply, brand)
    size, inner = supply.pack_sizes[brand.key] if supply.in_packs?
    t("supplies.brands.inside", count: t("supplies.units.#{inner}", count: brand.left * size)) if size
  end

  # "Each pack has" / "Each box has": the pack size row's label for each unit that has one
  def supply_pack_labels = Supply::PACKS.to_h { [ it, t("supplies.form.pack_size", unit: t("supplies.units.#{it}_one")) ] }

  # The pack-size controller's values on a form with supplies/_pack_size_field; `prefilled`: the size
  # in it came from the brand already typed in, so typing a new brand clears it
  def supply_pack_data(supply, prefilled: false)
    { pack_size_labels_value: supply_pack_labels.to_json, pack_size_sizes_value: supply.pack_sizes.to_json,
      pack_size_item_name_value: supply.name.to_s, pack_size_prefilled_value: prefilled.present? }
  end

  # "NT$289 for 12 · NT$24.1/roll". A narrow card breaks the line only between its parts, never inside
  # one ("NT$360 ⏎ for 6", "每捲 ⏎ NT$24.1")
  def supply_price_line(purchase)
    total = t("supplies.price_line", total: money(purchase.total_price, purchase.currency), quantity: purchase.quantity)
    supply_parts([ total, *supply_unit_price_parts(purchase) ])
  end

  # Parts joined with " · " where the line may break only after a dot, so a dot never starts a line.
  # Each text part stays whole (a store name, a price) unless listed in `wrap` (a long product name);
  # a part that is already HTML (another price line) keeps its own breaks. Nils are left out
  def supply_parts(parts, wrap: [])
    parts = parts.compact.map do |part|
      part.html_safe? || wrap.include?(part) ? part : tag.span(part, class: "whitespace-nowrap")
    end
    safe_join(parts, PART_SEPARATOR)
  end

  PART_SEPARATOR = "\u00A0· ".freeze

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
      t("supplies.line.not_enough_data", button: supply_used_one(supply))
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

  # What a purchase cost: "NT$250", and for one made abroad the price there in brackets,
  # "NT$250 (JP¥1,196)"
  def supply_cost(entry)
    home = money(entry.total_price, entry.currency)
    return home unless entry.paid_abroad?
    safe_join([ home, tag.span("(#{money(entry.paid_total, entry.paid_currency)})", class: "text-gray-600") ], " ")
  end

  # Price history, under a price paid abroad: "Paid JP¥1,196 by card, with fee" (the card's fee is in
  # the amount), "… by card, without fee", "… in cash"
  def supply_paid_line(entry)
    return unless entry.paid_abroad?
    how = if entry.paid_by == "cash" then "cash"
    elsif entry.paid_by != "card" then "plain"
    elsif entry.card_fee_included.nil? then "card"
    else entry.card_fee_included ? "card_with_fee" : "card_without_fee"
    end
    t("supplies.paid.line.#{how}", amount: money(entry.paid_total, entry.paid_currency))
  end

  # What the price field opens on (supplies/_price_field): the currency and the price as typed, how
  # it was paid, and the two home-currency boxes. A price paid abroad opens as it was saved (or as it
  # was typed, when the form was refused); anything else on what this household chose last time
  def supply_paid_form(record)
    home = Supplies::Currency[Current.household.default_currency]
    abroad = record.paid_abroad? && record.paid_currency != home.code
    last = Supplies::PaidAmount.defaults(Current.household)
    card = abroad && record.paid_by ? record.paid_by == "card" : last[:paid_by] == "card"
    included = abroad && !record.card_fee_included.nil? ? record.card_fee_included : last[:card_fee_included]
    # Saved, total_price is the home amount and paid_total the price; as typed, total_price is the price
    saved = record.total_price if abroad && record.paid_total
    { home:, entry: (Supplies::Currency[record.paid_currency] if abroad) || home, card:, included:,
      price: abroad ? record.paid_total || record.total_price : record.total_price,
      fee: (record.card_fee_percent if abroad) || last[:card_fee_percent],
      home_total: record.home_total.presence || (saved unless card && included),
      home_total_with_fee: record.home_total_with_fee.presence || (saved if card && included) }
  end

  # On a form with a price field: what paid_currency_controller works with. The currencies, where
  # to ask for a rate, and the lines it writes under the amounts, with the numbers left for it to
  # fill in. unit: the item's unit ("piece"), for "NT$125 a piece"; without one (a new item, whose
  # unit can still change) the lines leave the price per unit out
  def supply_paid_data(unit: nil)
    home = Supplies::Currency[Current.household.default_currency]
    blank = { price: "%{price}", typed: "%{typed}", app: "%{app}" }
    texts = %w[card cash typed].flat_map do |mode|
      [ [ "#{mode}Plain", t("supplies.paid.hint.#{mode}_plain", **blank) ], ([ mode, t("supplies.paid.hint.#{mode}", unit:, **blank) ] if unit) ].compact
    end.to_h
    texts.merge!(rate: t("supplies.paid.rate_line", one: "%{one}", rate: "%{rate}", date: "%{date}"), useApp: t("supplies.paid.use_app", app: "%{app}"),
                 noRate: t("supplies.paid.no_rate", currency: "%{currency}", symbol: home.symbol), withFee: t("supplies.paid.with_fee", percent: "%{percent}"),
                 amount: t("supplies.paid.amount", symbol: home.symbol), amountToSave: t("supplies.paid.amount_to_save", symbol: home.symbol))
    { controller: "paid-currency", paid_currency_home_value: home.code, paid_currency_locale_value: I18n.locale,
      paid_currency_url_value: exchange_rate_household_supplies_path(Current.household), paid_currency_texts_value: texts.to_json,
      paid_currency_currencies_value: Supplies::Currency::ALL.transform_values { { symbol: it.symbol, decimals: it.decimals } }.to_json }
  end

  # A number box's value without a pointless ".0": 1196, 18.99
  def supply_amount_value(amount)
    return if amount.blank?
    amount = amount.to_d
    amount == amount.round ? amount.to_i : amount
  end

  # A History line: "+12 · NT$289 · Costco", "Counted: 4 rolls", or with the brand a −1 named
  # "Used 1 · Pantene Shampoo 700ml · 1 bottle left"
  def supply_history_line(supply, event)
    if event.is_a?(SupplyPurchase)
      safe_join([ "+#{supply_count(supply, event.quantity)}", supply_cost(event), event.store.presence,
                  (tag.span(event.product_name, class: "font-semibold") if event.product_name) ].compact, " · ")
    elsif event.used_product.present?
      safe_join([ t("supplies.show.used_line"), tag.span(event.used_product, class: "font-semibold"), t("supplies.show.left_line", left: supply_count(supply, event.level)) ], " · ")
    else
      t("supplies.show.counted_line", left: supply_count(supply, event.level))
    end
  end


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

  # A filter on Supplies › All: a switch. Chosen it is blue with a ✕, and its link leads to the list
  # without it; otherwise the link adds it to the ones already chosen
  def supply_filter_chip(label, path, chosen:, count: nil)
    tone = chosen ? "border-blue-700 bg-blue-100 font-bold text-blue-900" : "border-(--card-line) bg-white font-semibold"
    link_to path, class: "inline-flex min-h-9 items-center gap-1 rounded-full border-2 px-3 text-sm #{tone}", "aria-current": (chosen ? "true" : nil) do
      parts = [ tag.span(label) ]
      parts << tag.span(count, class: "font-extrabold") if count
      if chosen
        parts << tag.svg(tag.path(d: "M6 6l12 12M18 6L6 18"), class: "h-4 w-4", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
                         "stroke-width": "2.6", "stroke-linecap": "round", "aria-hidden": "true")
        parts << tag.span(t("supplies.index.chosen"), class: "sr-only")
      end
      safe_join(parts, " ")
    end
  end

  # The languages this ledger is read in: what each member chose in My Account, and the one on screen
  def ledger_locales
    @ledger_locales ||= (Current.household.memberships.includes(:user).filter_map { it.user.locale.presence } + [ I18n.locale.to_s ]).uniq
  end

  # "zh-TW" or "en" when a supply category has no name in a language the ledger is read in
  def supply_category_missing_name(category) = category.missing_locale.then { it if ledger_locales.include?(it) }
end
