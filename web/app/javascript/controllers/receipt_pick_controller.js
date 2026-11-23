import { Controller } from "@hotwired/stimulus"

// Review items: how many lines each invoice will add ("2 of 4 lines will be added"), its Tick all /
// Untick all, and the count on Save. A line counts while ticked, on an invoice that is not excluded
// (and, under Not included, only once "Include anyway" is ticked)
export default class extends Controller {
  static targets = ["add", "count", "toggle", "save"]
  static values = { texts: Object }

  connect() { this.update() }

  toggle(event) {
    const key = event.currentTarget.dataset.key
    const mine = this.linesOf(key)
    const tick = !mine.every((box) => box.checked)
    mine.forEach((box) => {
      if (box.checked === tick) return
      box.checked = tick
      box.dispatchEvent(new Event("change", { bubbles: true }))
    })
    this.update()
  }

  update() {
    this.countTargets.forEach((count) => {
      const mine = this.linesOf(count.dataset.key)
      const ticked = mine.filter((box) => box.checked).length
      count.textContent = this.fill(this.textsValue.will_add, { count: ticked, total: mine.length })
    })
    this.toggleTargets.forEach((button) => {
      const mine = this.linesOf(button.dataset.key)
      button.textContent = mine.length && mine.every((box) => box.checked) ? this.textsValue.untick_all : this.textsValue.tick_all
    })
    if (this.hasSaveTarget) {
      const adding = this.addTargets.filter((box) => box.checked && this.importing(box)).length
      this.saveTarget.textContent = adding ? this.fill(this.textsValue.save_count, { count: adding }) : this.textsValue.save
    }
  }

  linesOf(key) { return this.addTargets.filter((box) => box.dataset.key === key) }

  // Whether Save adds the invoice this line is on
  importing(box) {
    const invoice = box.closest("section")
    if (invoice?.querySelector(".receipt-exclude:checked")) return false
    const folded = box.closest("details")
    return !folded || !!folded.querySelector(".receipt-include:checked")
  }

  fill(text, values) {
    const many = values.count === 1 ? text.one : text.other
    return Object.entries(values).reduce((out, [ name, value ]) => out.replaceAll(`%{${name}}`, value), many ?? text)
  }
}
