import { Controller } from "@hotwired/stimulus"

// Record form: the repeating reminder (Reminder (No Due Date), Start Reminding On) only applies to
// records without a due date, so it's hidden while a due date is filled in
export default class extends Controller {
  static targets = ["due", "reminder"]

  connect() {
    this.toggle()
  }

  toggle() {
    this.reminderTarget.hidden = this.dueTarget.value !== ""
  }
}
