import { Controller } from "@hotwired/stimulus"

// Bought more, Edit and Log a purchase…: a dialog over the page on a computer (loaded into the layout's
// "modal" Turbo Frame), their own page on a phone.
//
// The target is set as soon as the link appears (and again when the window crosses 1024px), not on
// click: Turbo prefetches a link on hover, and a prefetch made before data-turbo-frame was set asks
// for the whole page. The click then reused that page, which has only an empty "modal" frame, so the
// dialog didn't open until a second click.
export default class extends Controller {
  connect() {
    this.query = window.matchMedia("(min-width: 1024px)")
    this.update = () => this.route()
    this.query.addEventListener("change", this.update)
    this.route()
  }

  disconnect() {
    this.query.removeEventListener("change", this.update)
  }

  route() {
    if (this.query.matches) this.element.dataset.turboFrame = "modal"
    else delete this.element.dataset.turboFrame
  }
}
