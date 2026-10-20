import { Controller } from "@hotwired/stimulus"

// "Install app" (PRD §16): shown only when the browser offers installation (Android/desktop Chrome).
// Chrome fires beforeinstallprompt once per full page load, but Turbo replaces the header on every
// link click, so the event is kept here at module level and every new header picks it up.
let deferred = null
const listeners = new Set()
const notify = () => listeners.forEach((update) => update())

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault()
  deferred = event
  notify()
})
window.addEventListener("appinstalled", () => {
  deferred = null
  notify()
})

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.update = () => { this.buttonTarget.hidden = !deferred }
    listeners.add(this.update)
    this.update()
  }

  disconnect() {
    listeners.delete(this.update)
  }

  async install() {
    if (!deferred) return
    const prompt = deferred
    deferred = null // a prompt can be shown only once; Chrome sends a new event if it can ask again
    prompt.prompt()
    await prompt.userChoice
    notify()
  }
}
