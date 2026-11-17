import { Controller } from "@hotwired/stimulus"

// The supply item form's Category: choosing "＋ New category…" shows the field for its name
export default class extends Controller {
  static targets = ["select", "field", "input"]

  toggle() {
    const adding = this.selectTarget.value === "new"
    this.fieldTarget.hidden = !adding
    this.inputTarget.required = adding
    if (adding) this.inputTarget.focus()
  }
}
