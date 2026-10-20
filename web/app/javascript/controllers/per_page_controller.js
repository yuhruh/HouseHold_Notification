import { Controller } from "@hotwired/stimulus"

// Records "per page": a preset (10 / 20 / 50) applies at once; Custom shows a number box and Go
export default class extends Controller {
  static targets = ["select", "custom"]

  change() {
    const custom = this.selectTarget.value === "custom"
    this.customTarget.hidden = !custom
    if (custom) this.customTarget.querySelector("input").focus()
    else this.element.requestSubmit()
  }
}
