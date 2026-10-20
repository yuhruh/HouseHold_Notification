import { Controller } from "@hotwired/stimulus"

// Record form "Amount paid": Not paid yet clears the payment, Paid in full copies the amount due
// (and follows it), Partly paid takes an amount up to the amount due. Choosing a payment fills an
// empty paid date with today
export default class extends Controller {
  static targets = ["due", "paid", "paidField", "paidOn", "choice"]

  connect() {
    this.show(false)
  }

  choose() {
    this.show(true)
  }

  sync() {
    if (this.selected === "full") this.paidTarget.value = this.dueTarget.value
    this.paidTarget.max = this.dueTarget.value
  }

  show(changed) {
    const choice = this.selected
    this.paidFieldTarget.hidden = choice !== "partial"
    this.paidTarget.max = this.dueTarget.value
    if (!changed) return

    if (choice === "none") {
      this.paidTarget.value = ""
      this.paidOnTarget.value = ""
      return
    }
    if (choice === "full") this.paidTarget.value = this.dueTarget.value
    if (choice === "partial") {
      if (this.paidTarget.value === this.dueTarget.value) this.paidTarget.value = ""
      this.paidTarget.focus()
    }
    if (this.paidOnTarget.value === "") this.paidOnTarget.value = new Date().toLocaleDateString("en-CA")
  }

  get selected() {
    return this.choiceTargets.find((radio) => radio.checked)?.value
  }
}
