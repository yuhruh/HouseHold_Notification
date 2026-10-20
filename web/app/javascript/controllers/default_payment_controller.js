import { Controller } from "@hotwired/stimulus"

// New record: choosing a category fills in the payment method last used in that category, unless
// the payment method was already picked by hand
export default class extends Controller {
  static targets = ["category", "payment"]
  static values = { map: Object }

  apply() {
    const current = this.paymentTarget.value
    if (current !== "" && current !== this.filled) return
    const pm = this.mapValue[this.categoryTarget.value]
    this.paymentTarget.value = pm ? String(pm) : ""
    this.filled = this.paymentTarget.value
  }
}
