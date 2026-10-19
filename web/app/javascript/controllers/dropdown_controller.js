import { Controller } from "@hotwired/stimulus"

// Closes a <details> menu (languages, household switcher) on a click outside it or on Escape
export default class extends Controller {
  connect() {
    this.close = (event) => {
      if (event.type === "keydown" ? event.key === "Escape" : !this.element.contains(event.target)) {
        this.element.open = false
      }
    }
    document.addEventListener("click", this.close)
    document.addEventListener("keydown", this.close)
  }

  disconnect() {
    document.removeEventListener("click", this.close)
    document.removeEventListener("keydown", this.close)
  }
}
