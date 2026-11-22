import { Controller } from "@hotwired/stimulus"

// The item form's "Each pack has [4] [pieces]": shown only while Counted in is a pack, box or bag
// (labels: their words, "Each box has"), and left out of Save otherwise
export default class extends Controller {
  static targets = ["unit", "row", "label"]
  static values = { labels: Object }

  connect() { this.toggle() }

  toggle() {
    const label = this.labelsValue[this.unitTarget.value]
    this.rowTarget.hidden = !label
    this.rowTarget.querySelectorAll("input, select").forEach((field) => { field.disabled = !label })
    if (label) this.labelTarget.textContent = label
  }
}
