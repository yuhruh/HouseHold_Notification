import { Controller } from "@hotwired/stimulus"

// Header hamburger (under 1550px): opens the full-screen menu as a modal dialog (Escape closes it),
// and closes it before Turbo caches the page or follows a link from it
export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.beforeCache = () => this.close()
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.dialogTarget.addEventListener("click", (event) => { if (event.target.closest("a")) this.close() })
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }
}
