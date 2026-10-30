import { Controller } from "@hotwired/stimulus"

// Keeps an open app on the latest version (About This App). On load, when the app comes back to the
// screen and every 30 minutes it asks /version for the server's build; when that differs from the
// build this page was rendered with, it refreshes the service worker and reloads. If a form on the
// page has been changed, it asks first instead of reloading. After an update it shows a card with
// what's new since the version this device last saw, and marks About This App New (menu row, a dot
// on your photo, the versions on the page) until you open it. Turbo also reloads on navigation,
// because the app-build meta tag is tracked.
const SEEN = "app-update-seen"
const UNREAD = "app-update-unread"
const CHECK_EVERY = 30 * 60 * 1000
const MIN_GAP = 5 * 60 * 1000
let lastCheck = 0

const read = (key) => { try { return JSON.parse(localStorage.getItem(key)) } catch (_) { return null } }
const write = (key, value) => { try { localStorage.setItem(key, JSON.stringify(value)) } catch (_) {} }
const readSeen = () => read(SEEN)
const writeSeen = (seen) => write(SEEN, seen)
const readUnread = () => (Array.isArray(read(UNREAD)) ? read(UNREAD) : [])
const addUnread = (entries) => write(UNREAD, [...new Set([...readUnread(), ...entries.map((entry) => entry.version)])])

export default class extends Controller {
  static targets = ["toast", "title", "notes", "reload", "status", "card", "cardTitle", "cardNote", "newBadge", "about"]
  static values = { url: String, version: String, build: String, strings: Object }

  newBadgeTargetConnected(badge) {
    badge.hidden = readUnread().length === 0
  }

  // About This App: tag the versions that are new to this device, then they're read; and check now
  aboutTargetConnected(page) {
    this.tagNew(readUnread())
    write(UNREAD, [])
    this.newBadgeTargets.forEach((badge) => { badge.hidden = true })
    this.checkNow()
  }

  // The versions' New tag on About This App
  tagNew(versions) {
    this.aboutTarget.querySelectorAll("[data-version]").forEach((entry) => {
      if (versions.includes(entry.dataset.version)) entry.querySelector("[data-new-tag]").hidden = false
    })
  }

  closeCard() {
    this.cardTarget.hidden = true
  }

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
    if (this.pending) {
      writeSeen({ version: this.pending.version, build: this.pending.build })
      addUnread(this.pending.notes)
    }
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
      if (!data.notes.length) return
      // Updated while on About This App: the page itself shows what's new
      if (this.hasAboutTarget) return this.tagNew(data.notes.map((entry) => entry.version))
      addUnread(data.notes)
      this.newBadgeTargets.forEach((badge) => { badge.hidden = false })
      if (this.hasCardTarget) this.showCard(data)
      else this.showToast(this.stringsValue.updated.replace("%{version}", data.version), data.notes, false)
    } catch (_) {}
  }

  // Signed in: the newest change in a card at the top of the page; See What's New lists them all
  showCard(data) {
    this.cardTitleTarget.textContent = this.stringsValue.updated_short.replace("%{version}", data.version)
    this.cardNoteTarget.textContent = data.notes[0].notes[0] ?? ""
    this.cardTarget.hidden = false
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
