import { Controller } from "@hotwired/stimulus"

// "‹ Back" above every signed-in page. The installed app has no browser back button, so this
// goes back in history; opened fresh (from a notification or an email link) there's nothing to go
// back to, so it follows its href (the household home) instead.
export default class extends Controller {
  go(event) {
    if (window.history.length > 1) {
      event.preventDefault()
      window.history.back()
    }
  }
}
