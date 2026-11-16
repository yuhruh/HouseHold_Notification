import { Controller } from "@hotwired/stimulus"

// ‹ Back to Supplies leads back to the Supplies view you came from: the tab, filter, category and search.
// On <body>: the Supplies list remembers its address for this browser tab (sessionStorage, so two tabs
// never interfere), an item's pages (item, edit, purchase, scan, receipt) point their back link at it,
// and any other page forgets it, so an item opened from somewhere else goes back to Supplies as it opens
export default class extends Controller {
  static targets = ["link"]
  static values = { list: String }

  connect() {
    const list = this.listValue
    const here = window.location.pathname
    try {
      if (list && here === list) {
        sessionStorage.setItem("suppliesView", here + window.location.search)
      } else if (list && here.startsWith(`${list}/`)) {
        const view = sessionStorage.getItem("suppliesView")
        if (view && view.split("?")[0] === list && this.hasLinkTarget) this.linkTarget.href = view
      } else {
        sessionStorage.removeItem("suppliesView")
      }
    } catch {
      // No storage (private mode, blocked site data): the link keeps leading to Supplies as it opens
    }
  }
}
