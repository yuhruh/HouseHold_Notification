import { Controller } from "@hotwired/stimulus"

// Header hamburger and the tab bar's New (under 1550px): opens the full-screen menu or the Add new sheet
// as a modal dialog. Escape, its Cancel / ✕ or a click outside it (on the backdrop) closes it, and so
// does Turbo caching the page or following a link from it
export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.beforeCache = () => this.close()
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.dialogTarget.addEventListener("click", (event) => { if (event.target.closest("a") || this.outside(event)) this.close() })
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  // A click on the backdrop lands on the dialog itself, outside its box (its own padding is inside)
  outside(event) {
    if (event.target !== this.dialogTarget) return false
    const box = this.dialogTarget.getBoundingClientRect()
    return event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom
  }

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }
}
