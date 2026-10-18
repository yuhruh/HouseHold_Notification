import { Controller } from "@hotwired/stimulus"

// Fills a hidden tz field with the browser's IANA zone; the server validates it (PRD §11).
export default class extends Controller {
  static targets = ["field"]

  connect() {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
    this.fieldTargets.forEach((field) => { field.value = zone || "" })
  }
}
