import { Controller } from "@hotwired/stimulus"

// 從備註指定付款方式: ↑/↓ reorder the keyword cards (a note matching several uses the first) and
// recount how many records each choice fills, as the server will when the form is applied
export default class extends Controller {
  static targets = ["list", "card", "count", "summary"]
  static values = { matches: Array, unmatched: Number, summary: String, count: String }

  up(event) {
    const card = event.target.closest("[data-note-keywords-target=card]")
    if (card.previousElementSibling) this.listTarget.insertBefore(card, card.previousElementSibling)
    this.recount()
  }

  down(event) {
    const card = event.target.closest("[data-note-keywords-target=card]")
    if (card.nextElementSibling) this.listTarget.insertBefore(card.nextElementSibling, card)
    this.recount()
  }

  recount() {
    const choices = new Map(this.cardTargets.map((card) => [card.dataset.keyword, card.querySelector("select").value]))
    const counts = new Map([...choices.keys()].map((k) => [k, 0]))
    for (const list of this.matchesValue) {
      const keyword = [...choices.keys()].find((k) => list.includes(k) && choices.get(k) !== "skip")
      if (keyword) counts.set(keyword, counts.get(keyword) + 1)
    }
    this.cardTargets.forEach((card) => {
      card.querySelector("[data-note-keywords-target=count]").textContent = this.countValue.replace("%{count}", counts.get(card.dataset.keyword))
    })
    const records = [...counts.values()].reduce((a, b) => a + b, 0)
    const methods = new Set([...choices].filter(([k, c]) => counts.get(k) > 0 && c.startsWith("new:")).map(([, c]) => c)).size
    this.summaryTarget.textContent = this.summaryValue.replace("%{records}", records).replace("%{methods}", methods).replace("%{unmatched}", this.unmatchedValue)
  }
}
