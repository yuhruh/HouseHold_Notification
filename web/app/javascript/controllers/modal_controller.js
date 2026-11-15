import { Controller } from "@hotwired/stimulus"

// The dialog a page opens in when it's loaded into the "modal" frame: shown at once; Escape, Cancel or
// a click on the backdrop closes it and empties the frame, so the next one starts fresh
export default class extends Controller {
  connect() {
    this.element.showModal()
    this.element.addEventListener("close", () => this.clear())
    this.element.addEventListener("click", (event) => { if (event.target === this.element) this.close() })
    this.beforeCache = () => this.close()
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  close() {
    if (this.element.open) this.element.close()
  }

  clear() {
    const frame = this.element.closest("turbo-frame")
    if (frame) { frame.removeAttribute("src"); frame.innerHTML = "" }
  }
}
