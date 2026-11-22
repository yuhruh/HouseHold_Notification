import { Controller } from "@hotwired/stimulus"

// A line on Review items: "Add as new supply…" opens its New supply box (name, category, unit) and
// puts the cursor on the name; anything else closes it, and its fields are then left out of Save, so
// an empty "New category name" there never holds the form back
export default class extends Controller {
  static targets = ["choice", "box", "name"]

  connect() { this.sync() }

  toggle() {
    if (this.sync()) this.nameTarget.focus()
  }

  sync() {
    const adding = this.choiceTarget.value === "new"
    this.boxTarget.hidden = !adding
    this.boxTarget.querySelectorAll("input, select").forEach((field) => { field.disabled = !adding })
    return adding
  }
}
