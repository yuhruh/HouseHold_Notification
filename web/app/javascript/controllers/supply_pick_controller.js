import { Controller } from "@hotwired/stimulus"

// "What did you buy?": typing narrows the list; a group with nothing left hides
export default class extends Controller {
  static targets = ["query", "item", "group"]

  filter() {
    const query = this.queryTarget.value.trim().toLowerCase()
    this.itemTargets.forEach((item) => { item.hidden = query !== "" && !item.dataset.name.includes(query) })
    this.groupTargets.forEach((group) => { group.hidden = !group.querySelector("li:not([hidden])") })
  }
}
