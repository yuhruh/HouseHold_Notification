import { Controller } from "@hotwired/stimulus"

// On a form: a field with data-action="auto-submit#submit" sends the form as soon as it changes,
// e.g. a filter's select, or a file input that uploads the picked photo straight away. The label
// target, if there is one, shows the busy text meanwhile.
export default class extends Controller {
  static targets = ["label"]
  static values = { busy: String }

  submit(event) {
    const field = event.target
    if (field.type === "file" && !field.files.length) return
    if (this.hasLabelTarget && this.busyValue) this.labelTarget.textContent = this.busyValue
    this.element.requestSubmit()
  }
}
