import { Controller } from "@hotwired/stimulus"

// A supply's price typed in another currency (supplies/_price_field and _paid_panel): choose JPY,
// type the yen price, and the amount in the household's currency is worked out from the rate for
// the day it was bought (the form's date, not today).
//
//   Paid with Credit card: a Card fee box and two amounts, without the fee (price × rate) and with
//   it (price × rate × (1 + fee%)). The one chosen is saved. Changing the fee changes the second
//   amount and its label at once.
//   Paid with Cash: one amount, the rate alone.
//
// Under the amounts: the rate and the day it is for. An amount can be typed over (a statement that
// says something else): it then stays as typed, and "Use the app's figure" brings the app's back.
// With no rate to be had (offline, the service is down) the panel turns amber and asks for the
// amount, so saving never waits for a rate. On the household's own currency the panel is hidden and
// nothing in it is sent.
//
// The figures here are a preview: saving works the amount out again (Supplies::PaidAmount). They
// are computed in whole numbers so both come to the same.
export default class extends Controller {
  static targets = ["currency", "code", "price", "quantity", "date", "panel", "paidBy", "feeField", "fee", "amounts", "legend", "choice",
                    "choiceLabel", "withRow", "withLabel", "without", "withFee", "rateLine", "rateDay", "hint", "noRate", "useApp", "retry"]
  static values = { home: String, url: String, locale: String, currencies: Object, texts: Object }

  connect() {
    this.rate = undefined // undefined: not known yet; null: none to be had; else the rate, as text
    this.figures = {} // the app's own amounts: without the fee, with it
    this.typed = new Set() // the boxes typed over by hand
    this.opening = true // the boxes still hold what the form opened with
    this.refresh()
  }

  // The currency or the date changed: the rate is asked for again
  refresh() {
    const code = this.currencyTarget.value
    const on = this.hasDateTarget ? this.dateTarget.value : ""
    const asking = `${code} ${on}`
    if (code === this.homeValue || (asking === this.asked && this.rate)) return this.render()

    this.asked = asking
    this.rate = on ? undefined : null
    this.render()
    if (!on) return

    fetch(`${this.urlValue}?${new URLSearchParams({ from: code, on })}`, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      .then((response) => (response.ok ? response.json() : null))
      .catch(() => null)
      .then((answer) => {
        if (asking !== this.asked) return
        this.rate = answer?.rate || null
        this.ratedOn = answer?.on || on
        this.render()
      })
  }

  retry() {
    this.asked = null
    this.refresh()
  }

  // An amount is being typed over: it stays as typed
  typedOver(event) {
    this.typed.add(this.keyOf(event.target))
    this.describe()
  }

  // Left empty, or the same as the app's figure: it follows the rate again
  settled(event) {
    const key = this.keyOf(event.target)
    if (event.target.value === "" || Number(event.target.value) === this.figures[key]) this.typed.delete(key)
    this.render()
  }

  useApp() {
    this.typed.delete(this.chosen)
    this.render()
  }

  render() {
    const code = this.currencyTarget.value
    const abroad = code !== this.homeValue
    this.codeTarget.textContent = code
    this.priceTarget.step = this.currenciesValue[code].decimals ? "0.01" : "1"
    this.show(this.panelTarget, abroad)
    if (!abroad) return

    const none = this.rate === null
    const single = this.single
    this.panelTarget.classList.toggle("bg-sky-50", !none)
    this.panelTarget.classList.toggle("text-sky-900", !none)
    this.panelTarget.classList.toggle("bg-amber-50", none)
    this.panelTarget.classList.toggle("text-amber-900", none)
    this.show(this.feeFieldTarget, this.card && !none)
    this.amountsTarget.toggleAttribute("data-single", single)
    this.show(this.withRowTarget, !single)
    this.show(this.choiceLabelTarget, !single)
    this.legendTarget.textContent = single ? this.textsValue.amount : this.textsValue.amountToSave
    this.withLabelTarget.textContent = this.textsValue.withFee.replace("%{percent}", this.feeText)
    this.withoutTarget.required = none
    // One box, and the amount was in the other: it is still the amount
    if (none && this.withoutTarget.value === "" && this.withFeeTarget.value !== "") this.withoutTarget.value = this.withFeeTarget.value

    this.work()
    this.describe()
  }

  // The app's amounts, into every box that wasn't typed over
  work() {
    this.figures = {}
    if (!this.rate) return
    const price = this.scaled(this.priceTarget.value, 2)
    const rate = this.scaled(this.rate, 8)
    const fee = this.scaled(this.feeTarget.value === "" ? "0" : this.feeTarget.value, 2)
    if (price === null || rate === null) return

    this.figures.without = this.amount(price, rate, 0n)
    if (this.card && fee !== null && fee <= 1000n) this.figures.withFee = this.amount(price, rate, fee)
    for (const [key, box] of [["without", this.withoutTarget], ["withFee", this.withFeeTarget]]) {
      const figure = this.figures[key]
      if (figure === undefined) continue
      // What the form opened with (a saved purchase, or one sent back) and isn't the app's figure was typed
      if (this.opening && box.value !== "" && Number(box.value) !== figure) this.typed.add(key)
      if (!this.typed.has(key)) box.value = figure
    }
    this.opening = false
  }

  // The lines under the amounts: the rate and its day, what is saved, or that there is no rate
  describe() {
    const texts = this.textsValue
    const code = this.currencyTarget.value
    const none = this.rate === null
    const key = this.chosen
    const box = key === "without" ? this.withoutTarget : this.withFeeTarget
    const figure = this.figures[key]
    const typed = this.typed.has(key) && box.value !== "" && figure !== undefined && Number(box.value) !== figure
    for (const other of [this.withoutTarget, this.withFeeTarget]) {
      for (const mark of ["border-blue-600", "ring-1", "ring-blue-600"]) other.classList.toggle(mark, typed && other === box)
    }

    this.show(this.rateLineTarget, Boolean(this.rate))
    this.show(this.rateDayTarget, Boolean(this.rate))
    if (this.rate) {
      const one = `${this.currenciesValue[code].symbol}1`
      const worth = `${this.currenciesValue[this.homeValue].symbol}${Number(Number(this.rate).toPrecision(4))}`
      this.rateLineTarget.textContent = this.fill(texts.rate, { one, rate: worth, date: this.day(this.ratedOn) })
    }

    const total = box.value === "" ? null : Number(box.value)
    const quantity = this.hasQuantityTarget ? parseInt(this.quantityTarget.value, 10) : NaN
    const each = total !== null && quantity > 0 ? this.unitPrice(total / quantity) : null
    const mode = typed ? "typed" : this.card ? "card" : "cash"
    const text = (each && texts[mode]) || texts[`${mode}Plain`]
    this.show(this.hintTarget, Boolean(this.rate))
    this.hintTarget.textContent = this.fill(text, { price: each, typed: this.money(total), app: this.money(figure) })
    this.show(this.useAppTarget, typed)
    this.useAppTarget.textContent = this.fill(texts.useApp, { app: this.money(figure) })
    this.show(this.noRateTarget, none)
    this.noRateTarget.textContent = this.fill(texts.noRate, { currency: code })
    this.show(this.retryTarget, none)
  }

  get card() {
    return this.paidByTargets.find((radio) => radio.checked)?.value !== "cash"
  }

  // One amount box: paid in cash, or there is no rate and the amount is asked for
  get single() {
    return !this.card || this.rate === null
  }

  get chosen() {
    return !this.single && this.choiceTargets.find((radio) => radio.checked)?.value === "1" ? "withFee" : "without"
  }

  get feeText() {
    const fee = parseFloat(this.feeTarget.value)
    return isNaN(fee) ? "0" : String(fee)
  }

  keyOf(box) {
    return box === this.withFeeTarget ? "withFee" : "without"
  }

  // Shown or not; what is hidden isn't sent with the form
  show(element, shown) {
    element.hidden = !shown
    for (const field of element.querySelectorAll("input, select, button")) field.disabled = !shown
  }

  // "1196" → 119600n, "0.20612" → 20612000n: a number as a whole number of its smallest part
  scaled(text, places) {
    const match = /^(\d+)(?:\.(\d+))?$/.exec(String(text).trim())
    if (!match) return null
    return BigInt(match[1] + (match[2] || "").padEnd(places, "0").slice(0, places))
  }

  // price × rate × (1 + fee%), to the household currency's decimals, a half rounded up
  amount(price, rate, fee) {
    const decimals = this.currenciesValue[this.homeValue].decimals
    const part = 10n ** BigInt(14 - decimals)
    return Number((price * rate * (10000n + fee) * 2n + part) / (part * 2n)) / 10 ** decimals
  }

  money(amount) {
    if (amount === null || amount === undefined || isNaN(amount)) return ""
    const home = this.currenciesValue[this.homeValue]
    const decimals = Number.isInteger(amount) ? 0 : Math.max(home.decimals, 1)
    return `${home.symbol}${amount.toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}`
  }

  // A price per unit the way the lists write it: 1 decimal, none from 100 up
  unitPrice(price) {
    const home = this.currenciesValue[this.homeValue]
    let decimals = price >= 100 || Number.isInteger(price) ? 0 : 1
    if (home.decimals && price < 100) decimals = home.decimals
    return `${home.symbol}${price.toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}`
  }

  // "2026-11-16" → "Nov 16, 2026", "2026年11月16日"
  day(date) {
    const day = new Date(`${date}T00:00:00Z`)
    if (isNaN(day)) return date
    return new Intl.DateTimeFormat(this.localeValue, { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" }).format(day)
  }

  fill(text, values) {
    return String(text || "").replace(/%\{(\w+)\}/g, (_, name) => values[name] ?? "")
  }
}
