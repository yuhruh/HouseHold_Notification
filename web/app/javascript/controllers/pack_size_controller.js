import { Controller } from "@hotwired/stimulus"

// "Each pack has [4] [pieces]" on a purchase or an old price (supplies/_pack_size_field).
// - On the item forms Counted in can change: the row shows only for a pack, box or bag (labels:
//   their words, "Each box has") and is left out of Save otherwise.
// - Each brand keeps its own size: typing a brand bought before (sizes: { "Brand A": [4, "piece"] },
//   "" for no brand, which the item's own name also is) fills it in; typing a new brand clears a size
//   filled that way, never one the person typed.
export default class extends Controller {
  static targets = ["unit", "row", "label", "product", "size", "inner"]
  static values = { labels: Object, sizes: Object, itemName: String, prefilled: Boolean }

  connect() {
    this.filled = this.prefilledValue
    this.toggle()
  }

  // The purchase part of Edit item is reloaded on its own when another product is chosen
  rowTargetConnected() { this.toggle() }

  toggle() {
    if (!this.hasUnitTarget) return
    const label = this.labelsValue[this.unitTarget.value]
    this.rowTargets.forEach((row) => {
      row.hidden = !label
      row.querySelectorAll("input, select").forEach((field) => { field.disabled = !label })
    })
    if (label) this.labelTargets.forEach((el) => { el.textContent = label })
  }

  fill() {
    if (!this.hasSizeTarget || !this.hasProductTarget) return
    const name = this.productTarget.value.trim().replace(/\s+/g, " ")
    const known = this.sizesValue[name === this.itemNameValue ? "" : name]
    if (known) {
      this.sizeTarget.value = known[0]
      if (this.hasInnerTarget) this.innerTarget.value = known[1]
      this.filled = true
    } else if (this.filled) {
      this.sizeTarget.value = ""
      this.filled = false
    }
  }

  typed() { this.filled = false }
}
