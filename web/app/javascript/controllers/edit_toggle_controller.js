import { Controller } from "@hotwired/stimulus"

// A setting shown read-only until its pencil is tapped: the pencil swaps in the built-in dropdown
// (and opens it where the browser allows); Cancel puts the saved value back and hides it again.
export default class extends Controller {
  static targets = ["view", "edit", "field"]

  connect() {
    this.saved = this.fieldTarget.value
  }

  edit() {
    this.viewTarget.hidden = true
    this.editTarget.hidden = false
    this.fieldTarget.focus()
    try { this.fieldTarget.showPicker() } catch {}
  }

  cancel() {
    this.fieldTarget.value = this.saved
    this.editTarget.hidden = true
    this.viewTarget.hidden = false
  }
}
