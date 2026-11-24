import { Controller } from "@hotwired/stimulus"

// "Also add to Ledger" on a form whose price is optional (Supplies › Add details): shown once a price
// is typed, and unticked again when the price is cleared, so an expense is never added with no amount
export default class extends Controller {
  static targets = ["box"]

  connect() { this.toggle() }

  toggle() {
    const price = this.element.querySelector("[name='supply_purchase[total_price]']")
    const priced = price && price.value.trim() !== ""
    this.boxTarget.hidden = !priced
    if (!priced) this.boxTarget.querySelector("input[type=checkbox]").checked = false
  }
}
