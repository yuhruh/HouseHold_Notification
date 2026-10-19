import { Controller } from "@hotwired/stimulus"

// "Install app" (PRD §16): shown only when the browser offers installation (Android/desktop Chrome)
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.buttonTarget.hidden = true
    this.onPrompt = (event) => {
      event.preventDefault()
      this.deferred = event
      this.buttonTarget.hidden = false
    }
    window.addEventListener("beforeinstallprompt", this.onPrompt)
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.onPrompt)
  }

  async install() {
    if (!this.deferred) return
    this.deferred.prompt()
    await this.deferred.userChoice
    this.deferred = null
    this.buttonTarget.hidden = true
  }
}
