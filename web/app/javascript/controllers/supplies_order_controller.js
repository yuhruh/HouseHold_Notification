import { Controller } from "@hotwired/stimulus"

// Supplies' lists put themselves in order. "Used 1" and the toast's Undo (a count saved or taken back)
// redraw the card or row where it is; right after, this fetches the same view again and morphs the
// list to match it, so the item moves to where a refresh would put it, and the tab counts, To Buy's
// group headings, "Next up" and "About a month" follow. The page doesn't scroll, and the toast (with
// its Undo) or the "used up" pop-up stays as it is.
// Only the latest answer is drawn, so taps in a row can't leave an older order on screen. Items slide
// to their new place, the one that travels furthest on top; with Reduce Motion on they just move.
export default class extends Controller {
  static targets = ["item"]

  disconnect() { this.latest = null }

  changed(event) {
    if (event.detail.success && event.target.matches("form[action*='/counts']")) this.reorder()
  }

  async reorder() {
    const request = (this.latest = {})
    let fresh
    try {
      const response = await fetch(window.location.href, { headers: { Accept: "text/html" } })
      if (!response.ok || response.redirected) return
      fresh = new DOMParser().parseFromString(await response.text(), "text/html").getElementById(this.element.id)
    } catch {
      return // offline: the list stays as it is until the next change or a refresh
    }
    if (request !== this.latest || !fresh) return

    const before = this.tops()
    window.Turbo.morphChildren(this.element, fresh, { callbacks: { beforeNodeMorphed: (element) => element.id !== "supply_toast" } })
    this.slide(before)
  }

  // Each item's distance from the top of the page, by its id (a morph may rebuild an item's element)
  tops() {
    return new Map(this.itemTargets.map((item) => [ item.id, item.getBoundingClientRect().top + window.scrollY ]))
  }

  slide(before) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const moves = this.itemTargets
      .map((item) => [ item, before.get(item.id) - (item.getBoundingClientRect().top + window.scrollY) ])
      .filter(([ , by ]) => Math.abs(by) >= 1)
    const furthest = Math.max(...moves.map(([ , by ]) => Math.abs(by)))
    for (const [ item, by ] of moves) {
      const animation = item.animate([ { transform: `translateY(${by}px)` }, { transform: "none" } ], { duration: 300, easing: "ease-out" })
      if (Math.abs(by) < furthest) continue
      item.style.zIndex = 1
      animation.onfinish = animation.oncancel = () => { item.style.zIndex = "" }
    }
  }
}
