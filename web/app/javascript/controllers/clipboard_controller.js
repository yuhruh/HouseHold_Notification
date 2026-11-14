import { Controller } from "@hotwired/stimulus"

// A Copy button: copies `text` and says so on the button for 2 seconds
export default class extends Controller {
  static values = { text: String, done: String }
  static targets = ["label"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
    } catch {
      return
    }
    const label = this.hasLabelTarget ? this.labelTarget : this.element
    const before = label.textContent
    label.textContent = this.doneValue
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { label.textContent = before }, 2000)
  }
}
