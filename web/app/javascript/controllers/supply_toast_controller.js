import { Controller } from "@hotwired/stimulus"

// The toast after −1 or a count ("Used 1 · 1 roll left", Undo): goes away by itself after a while
export default class extends Controller {
  connect() { this.timer = setTimeout(() => this.dismiss(), 8000) }
  disconnect() { clearTimeout(this.timer) }
  dismiss() { this.element.remove() }
}
