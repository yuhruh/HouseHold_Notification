import { Controller } from "@hotwired/stimulus"

// New supply item → "Read the name from a photo": a photo of the package is read on the device with
// Tesseract (Traditional Chinese + English, self-hosted under /vendor, loaded only when used). The
// photo never leaves the device. The lines it finds are offered as choices, the biggest text (most
// likely the product name) first; tapping one puts it in the Name field to edit.
const BASE = "/vendor/tesseract-5.1.1"
let workerLoading = null

export default class extends Controller {
  static targets = ["photo", "status", "choices", "name"]
  static values = { texts: Object }

  choose() { this.photoTarget.click() }

  async read() {
    const file = this.photoTarget.files[0]
    this.photoTarget.value = ""
    if (!file) return
    this.choicesTarget.replaceChildren()
    this.say(workerLoading ? this.textsValue.reading : this.textsValue.first_time)
    try {
      const canvas = await this.canvas(file)
      const worker = await this.worker()
      this.say(this.textsValue.reading)
      const { data } = await worker.recognize(canvas)
      this.show(this.lines(data))
    } catch (_) {
      this.say(this.textsValue.failed, "warn")
    }
  }

  // Text lines worth offering, biggest letters first (the median word height: line boxes can span
  // several rows): CJK spacing removed, unsure, short or garbled ones dropped
  lines(data) {
    const seen = new Set()
    return (data.lines || [])
      .map((line) => ({ text: this.clean(line.text), height: this.letterHeight(line), confidence: line.confidence }))
      .filter((line) => line.confidence >= 50 && line.text.length >= 2 && line.text.length <= 40 && /[\p{L}]/u.test(line.text))
      .sort((a, b) => b.height - a.height)
      .filter((line) => !seen.has(line.text) && seen.add(line.text))
      .slice(0, 8)
      .map((line) => line.text)
  }

  letterHeight(line) {
    const heights = (line.words || []).filter((word) => word.confidence >= 50).map((word) => word.bbox.y1 - word.bbox.y0).sort((a, b) => a - b)
    return heights.length ? heights[Math.floor(heights.length / 2)] : 0
  }

  clean(text) {
    return text.replace(/\s+/g, " ").trim()
      .replace(/(?<=[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}])\s+(?=[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}])/gu, "")
      .replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N})）]+$/gu, "")
  }

  show(lines) {
    if (lines.length === 0) return this.say(this.textsValue.nothing, "warn")
    this.say(this.textsValue.pick)
    for (const text of lines) {
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = text
      button.className = "btn-press cursor-pointer rounded-xl bg-white px-3 py-1.5 text-sm font-medium text-gray-900"
      button.addEventListener("click", () => this.use(text))
      this.choicesTarget.append(button)
    }
  }

  use(text) {
    this.nameTarget.value = text.slice(0, 60)
    this.nameTarget.classList.add("bg-green-50", "border-green-700")
    this.nameTarget.focus()
  }

  // The photo, scaled to at most 2000px on its long edge (sharp enough, quick on a phone)
  async canvas(file) {
    const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
    const scale = Math.min(1, 2000 / Math.max(bitmap.width, bitmap.height))
    const canvas = document.createElement("canvas")
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    return canvas
  }

  // One reader per page visit, kept for the next photo
  worker() {
    workerLoading ??= this.script().then(() => window.Tesseract.createWorker(["chi_tra", "eng"], 1, {
      workerPath: `${BASE}/worker.min.js`, corePath: `${BASE}/core`, langPath: `${BASE}/lang`, workerBlobURL: false, gzip: true
    })).catch((error) => { workerLoading = null; throw error })
    return workerLoading
  }

  script() {
    if (window.Tesseract) return Promise.resolve()
    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = `${BASE}/tesseract.min.js`
      script.onload = resolve
      script.onerror = reject
      document.head.append(script)
    })
  }

  say(text, tone) {
    this.statusTarget.hidden = false
    this.statusTarget.textContent = text
    this.statusTarget.className = `text-sm ${tone === "warn" ? "text-amber-900" : "text-gray-700"}`
  }
}
