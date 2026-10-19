import { Controller } from "@hotwired/stimulus"

// Remembers the dashboard's "by paid date / by billing period" choice per browser (PRD →
// Business rules): an address without ?mode= switches to the saved one.
export default class extends Controller {
  static values = { key: String, current: String, param: String }

  connect() {
    const url = new URL(window.location.href)
    let saved = null
    try { saved = localStorage.getItem(this.keyValue) } catch (_) {}
    if (!url.searchParams.has(this.paramValue) && saved && saved !== this.currentValue) {
      url.searchParams.set(this.paramValue, saved)
      window.Turbo.visit(url.toString(), { action: "replace" })
    }
  }

  save(event) {
    try { localStorage.setItem(this.keyValue, event.params.mode) } catch (_) {}
  }
}
