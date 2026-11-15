import { Controller } from "@hotwired/stimulus"

// Bought more, Edit and Log a purchase…: a dialog over the page on a computer (loaded into the layout's
// "modal" Turbo Frame), their own page on a phone
export default class extends Controller {
  route() {
    if (window.matchMedia("(min-width: 1024px)").matches) this.element.dataset.turboFrame = "modal"
    else delete this.element.dataset.turboFrame
  }
}
