import { Controller } from "@hotwired/stimulus"

// Keeps an open app on the latest version (Settings → App version). On load, when the app comes
// back to the screen and every 30 minutes it asks /version for the server's build; when that differs
// from the build this page was rendered with, it refreshes the service worker and reloads. If a form
// on the page has been changed, it asks first instead of reloading. After an update it shows what's
// new since the version this device last saw. Turbo also reloads on navigation, because the
// app-build meta tag is tracked.
const SEEN = "app-update-seen"
const CHECK_EVERY = 30 * 60 * 1000
const MIN_GAP = 5 * 60 * 1000
let lastCheck = 0

const readSeen = () => { try { return JSON.parse(localStorage.getItem(SEEN)) } catch (_) { return null } }
const writeSeen = (seen) => { try { localStorage.setItem(SEEN, JSON.stringify(seen)) } catch (_) {} }

export default class extends Controller {
  static targets = ["toast", "title", "notes", "reload", "status"]
  static values = { url: String, version: String, build: String, strings: Object }

  connect() {
    this.showWhatsNew()
    this.onVisible = () => { if (document.visibilityState === "visible") this.check() }
    document.addEventListener("visibilitychange", this.onVisible)
    this.timer = setInterval(() => this.check(), CHECK_EVERY)
    this.check()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    clearInterval(this.timer)
  }

  // Settings → Check for updates
  async checkNow() {
    this.setStatus(this.stringsValue.checking)
    const updated = await this.check({ force: true })
    if (updated === null) this.setStatus(this.stringsValue.failed)
    else if (!updated) this.setStatus(this.stringsValue.latest)
    else this.setStatus(this.pending ? this.stringsValue.ready : this.stringsValue.updating)
  }

  // true when a newer build was found (the page reloads or asks), false when this is the latest,
  // null when the server couldn't be reached
  async check({ force = false } = {}) {
    if (!force && Date.now() - lastCheck < MIN_GAP) return false
    lastCheck = Date.now()
    let data
    try {
      const response = await fetch(`${this.urlValue}?since=${encodeURIComponent(this.versionValue)}`, { cache: "no-store", headers: { Accept: "application/json" } })
      if (!response.ok) return null
      data = await response.json()
    } catch (_) {
      return null
    }
    if (data.build === this.buildValue) return false

    try { await (await navigator.serviceWorker?.getRegistration())?.update() } catch (_) {}
    if (this.editing()) {
      this.pending = data
      this.showToast(this.stringsValue.ready, data.notes, true)
    } else {
      window.location.reload()
    }
    return true
  }

  reload() {
    if (this.pending) writeSeen({ version: this.pending.version, build: this.pending.build })
    window.location.reload()
  }

  dismiss() {
    this.toastTarget.hidden = true
  }

  async showWhatsNew() {
    const seen = readSeen()
    writeSeen({ version: this.versionValue, build: this.buildValue })
    if (!seen || seen.build === this.buildValue) return
    try {
      const response = await fetch(`${this.urlValue}?since=${encodeURIComponent(seen.version)}`, { cache: "no-store", headers: { Accept: "application/json" } })
      const data = await response.json()
      if (data.notes.length) this.showToast(this.stringsValue.updated.replace("%{version}", data.version), data.notes, false)
    } catch (_) {}
  }

  showToast(title, entries, offerReload) {
    if (!this.hasToastTarget) return
    this.titleTarget.textContent = title
    this.notesTarget.replaceChildren(...entries.flatMap((entry) => entry.notes).map((note) => {
      const item = document.createElement("li")
      item.textContent = note
      return item
    }))
    this.reloadTarget.hidden = !offerReload
    this.toastTarget.hidden = false
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  // A field changed from what the page loaded with, so a reload would lose it
  editing() {
    return [...document.querySelectorAll("input, textarea, select")].some((field) => {
      if (field.closest("[data-app-update-ignore]")) return false
      if (field.type === "checkbox" || field.type === "radio") return field.checked !== field.defaultChecked
      if (field.tagName === "SELECT") {
        const options = [...field.options]
        if (field.multiple) return options.some((option) => option.selected !== option.defaultSelected)
        const initial = options.findIndex((option) => option.defaultSelected)
        return field.selectedIndex !== Math.max(initial, 0)
      }
      if (["hidden", "submit", "button", "file"].includes(field.type)) return field.type === "file" && field.files.length > 0
      return field.value !== field.defaultValue
    })
  }
}
