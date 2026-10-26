import { Controller } from "@hotwired/stimulus"

// Closes a <details> menu (languages, the household and your menus, Snooze / Remind Me Later) on a click
// outside it or on Escape; on a phone the header menus' backdrop closes them too (dropdown#hide)
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

  hide() {
    this.element.open = false
  }

  disconnect() {
    document.removeEventListener("click", this.close)
    document.removeEventListener("keydown", this.close)
  }
}
