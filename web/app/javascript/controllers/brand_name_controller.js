import { Controller } from "@hotwired/stimulus"

// "Product or brand" on Restock and Edit item: the item's own name there is saved as no brand, so a
// note says so while that is what's typed (spaces squeezed, as the server does)
export default class extends Controller {
  static targets = ["input", "note"]
  static values = { item: String }

  connect() { this.check() }

  check() {
    const typed = this.inputTarget.value.trim().replace(/\s+/g, " ")
    this.noteTarget.hidden = typed !== this.itemValue
  }
}
