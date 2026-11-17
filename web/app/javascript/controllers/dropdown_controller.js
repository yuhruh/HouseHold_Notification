import { Controller } from "@hotwired/stimulus"

// Closes a <details> menu (languages, the household and your menus, Snooze / Remind Me Later) on a click
// outside it or on Escape; on a phone the header menus' backdrop closes them too (dropdown#hide)
export default class extends Controller {
  static targets = ["panel"]

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

  // A menu low on the page (Supplies: "Which one did you use?") scrolls into view when it opens
  reveal() {
    if (this.element.open && this.hasPanelTarget) this.panelTarget.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  disconnect() {
    document.removeEventListener("click", this.close)
    document.removeEventListener("keydown", this.close)
  }
}
