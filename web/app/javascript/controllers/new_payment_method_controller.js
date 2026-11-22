import { Controller } from "@hotwired/stimulus"

// "+ New payment method…" on a Payment Method menu: picking it shows the fields for the new method (Last 4
// Digits only for Card and Bank). A name the household already has says so: saving uses that one
export default class extends Controller {
  static targets = ["menu", "fields", "name", "same", "kind", "last4", "last4Hint"]
  static values = { existing: Object, same: String }

  connect() {
    this.toggle()
    this.check()
  }

  toggle() {
    const open = this.menuTarget.value === "new"
    this.fieldsTarget.hidden = !open
    if (open && this.nameTarget.value === "" && document.activeElement === this.menuTarget) this.nameTarget.focus()
  }

  kind() {
    const digits = ["card", "bank"].includes(this.kindTarget.value)
    this.last4Target.hidden = !digits
    this.last4HintTarget.hidden = !digits
  }

  check() {
    const label = this.existingValue[this.nameTarget.value.trim().replace(/\s+/g, " ").toLowerCase()]
    this.sameTarget.hidden = !label
    if (label) this.sameTarget.textContent = this.sameValue.replace("%{name}", label)
  }
}
