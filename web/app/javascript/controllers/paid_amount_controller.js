import { Controller } from "@hotwired/stimulus"

// Record form "Amount paid": Not paid yet clears the payment, Paid in full copies the amount due
// (and follows it), Partly paid takes an amount up to the amount due. Choosing a payment fills an
// empty paid date with today. A partial amount over the amount due is marked red with a warning,
// and the form's save buttons are disabled until it's fixed. Whole-number currencies (TWD) take
// amounts without cents: switching to one rounds the amounts and steps the fields by 1
export default class extends Controller {
  static targets = ["due", "paid", "paidField", "paidOn", "choice", "warning", "currency"]
  static values = { whole: Array }

  connect() {
    this.show(false)
  }

  currency() {
    const whole = this.wholeValue.includes(this.currencyTarget.value)
    for (const field of [this.dueTarget, this.paidTarget]) {
      field.step = whole ? "1" : "0.01"
      if (whole && field.value !== "") field.value = Math.round(parseFloat(field.value))
    }
    this.sync()
  }

  choose() {
    this.show(true)
  }

  sync() {
    if (this.selected === "full") this.paidTarget.value = this.dueTarget.value
    this.paidTarget.max = this.dueTarget.value
    this.check()
  }

  check() {
    const due = parseFloat(this.dueTarget.value)
    const paid = parseFloat(this.paidTarget.value)
    const over = this.selected === "partial" && !isNaN(due) && !isNaN(paid) && paid > due
    this.warningTarget.hidden = !over
    this.paidTarget.classList.toggle("border-red-600", over)
    this.paidTarget.classList.toggle("ring-2", over)
    this.paidTarget.classList.toggle("ring-red-600", over)
    this.paidTarget.classList.toggle("border-gray-400", !over)
    if (over) this.paidTarget.setAttribute("aria-invalid", "true")
    else this.paidTarget.removeAttribute("aria-invalid")
    this.element.closest("form").querySelectorAll("input[type=submit], button[type=submit]").forEach((button) => { button.disabled = over })
  }

  show(changed) {
    const choice = this.selected
    this.paidFieldTarget.hidden = choice !== "partial"
    this.paidTarget.max = this.dueTarget.value
    if (changed) {
      if (choice === "none") {
        this.paidTarget.value = ""
        this.paidOnTarget.value = ""
      } else {
        if (choice === "full") this.paidTarget.value = this.dueTarget.value
        if (choice === "partial") {
          if (this.paidTarget.value === this.dueTarget.value) this.paidTarget.value = ""
          this.paidTarget.focus()
        }
        if (this.paidOnTarget.value === "") this.paidOnTarget.value = new Date().toLocaleDateString("en-CA")
      }
    }
    this.check()
  }

  get selected() {
    return this.choiceTargets.find((radio) => radio.checked)?.value
  }
}
