import { Controller } from "@hotwired/stimulus"

// A pop-up message shown as soon as the page opens (a barcode or receipt line no database knows):
// OK, Escape or a click outside closes it and moves the cursor to the field to fill in by hand
export default class extends Controller {
  static values = { focus: String }

  connect() {
    this.element.showModal()
    this.element.addEventListener("close", () => this.focusField(), { once: true })
    this.element.addEventListener("click", (event) => { if (event.target === this.element) this.element.close() })
  }

  close() { this.element.close() }

  focusField() {
    const field = this.focusValue && document.querySelector(this.focusValue)
    if (!field) return
    field.closest("details")?.setAttribute("open", "")
    field.focus()
  }
}
