import { Controller } from "@hotwired/stimulus"

// A line on Review items. Its tick box says whether it is added: unticked, its quantity is locked,
// its other fields fold away (all left out of Save) and "Not added" shows instead. "Add as new
// supply…" opens its New supply box (name, category, unit) and puts the cursor on the name; anything
// else closes it, and its fields are then left out of Save, so an empty "New category name" there
// never holds the form back
export default class extends Controller {
  static targets = ["add", "qty", "field", "off", "choice", "box", "name"]

  connect() { this.sync() }

  toggle(event) {
    const adding = this.sync()
    if (event?.target === this.choiceTarget && adding) this.nameTarget.focus()
  }

  sync() {
    const ticked = !this.hasAddTarget || this.addTarget.checked
    this.fieldTargets.forEach((field) => {
      field.hidden = !ticked
      field.querySelectorAll("input, select").forEach((input) => { input.disabled = !ticked })
    })
    this.qtyTargets.forEach((qty) => { qty.disabled = !ticked })
    this.offTargets.forEach((off) => { off.hidden = ticked })
    const adding = ticked && this.choiceTarget.value === "new"
    this.boxTarget.hidden = !adding
    this.boxTarget.querySelectorAll("input, select").forEach((field) => { field.disabled = !adding })
    return adding
  }
}
