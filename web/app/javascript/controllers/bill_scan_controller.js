import { Controller } from "@hotwired/stimulus"

// New Record → Scan the Bill's Barcodes (三段式條碼). The live camera (or a photo) is read on the phone:
// with the browser's own BarcodeDetector where it reads Code 39 (Android Chrome, Samsung Internet,
// desktop Chrome), otherwise with ZXing, loaded only then (iPhone and iPad in any browser, Safari,
// Firefox). Checked by what the browser can do, not by its name. Once all 3 barcodes are read, the
// server (bill_scans#show, Records::BillBarcode) says what they mean and the form is filled in: fields
// read straight from the barcodes are tagged "from barcode", guesses "please check". A biller code the
// household hasn't seen yet asks once which category it is (biller_codes#create). Before filling, a bill
// already recorded (same bill number) or maybe recorded (same category and period, typed in by hand)
// shows those records first; saying a similar one is this bill gives it the bill number (bill_scans#update).
const ZXING_URL = "/vendor/zxing-0.21.3.min.js"
const FIRST = /^(\d{6})([0-9A-Z]{3})$/
const THIRD = /^\d{4}[0-9A-Z]{2}\d{9}$/
const SECOND = /^[0-9A-Z]{6,20}$/
let zxingLoading = null

export default class extends Controller {
  static targets = ["card", "message", "photo", "dialog", "video", "tick", "light", "lightSpacer", "texts",
                    "ask", "askAmount", "askDeadline", "askBiller", "askOnce", "askCategory", "askOffset",
                    "match", "matchTitle", "matchLine", "matchList", "already", "similar", "openRecord"]
  static values = { scanUrl: String, rememberUrl: String }

  connect() { this.texts = JSON.parse(this.textsTarget.textContent) }
  disconnect() { this.stop() }

  // ---- Reading -------------------------------------------------------------------------------

  async open() {
    this.reset()
    this.dialogTarget.showModal()
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment", width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false })
    } catch (_) {
      this.dialogTarget.close()
      return this.say(this.texts.no_camera, "warn")
    }
    this.videoTarget.srcObject = this.stream
    await this.videoTarget.play().catch(() => {})
    const track = this.stream.getVideoTracks()[0]
    const torch = track.getCapabilities?.().torch
    this.lightTarget.hidden = !torch
    this.lightSpacerTarget.hidden = !!torch
    this.decode = await this.decoder()
    this.loop()
  }

  loop() {
    if (!this.stream) return
    const video = this.videoTarget
    if (video.videoWidth) {
      const canvas = this.frame(video, video.videoWidth, video.videoHeight)
      this.decode(canvas).then((codes) => this.found(codes)).finally(() => { this.timer = setTimeout(() => this.loop(), 200) })
    } else {
      this.timer = setTimeout(() => this.loop(), 200)
    }
  }

  async readPhoto() {
    const file = this.photoTarget.files[0]
    if (!file) return
    this.reset()
    this.say(this.texts.reading)
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
      const decode = await this.decoder()
      this.found(await decode(this.frame(bitmap, bitmap.width, bitmap.height, 2400)))
      if (!this.complete()) this.say(this.texts.not_found, "warn")
    } catch (_) {
      this.say(this.texts.not_found, "warn")
    }
    this.photoTarget.value = ""
  }

  photoInstead() {
    this.close()
    this.photoTarget.click()
  }

  close() { this.dialogTarget.close() }

  stop() {
    clearTimeout(this.timer)
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
  }

  toggleLight() {
    const track = this.stream?.getVideoTracks()[0]
    if (!track) return
    this.lit = !this.lit
    track.applyConstraints({ advanced: [{ torch: this.lit }] }).catch(() => {})
  }

  // The browser's own reader when it reads Code 39, else ZXing
  async decoder() {
    if ("BarcodeDetector" in window) {
      const formats = await window.BarcodeDetector.getSupportedFormats().catch(() => [])
      if (formats.includes("code_39")) {
        const detector = new window.BarcodeDetector({ formats: ["code_39"] })
        return async (canvas) => (await detector.detect(canvas).catch(() => [])).map((code) => code.rawValue)
      }
    }
    const ZXing = await this.loadZxing()
    const hints = new Map([[ZXing.DecodeHintType.POSSIBLE_FORMATS, [ZXing.BarcodeFormat.CODE_39]], [ZXing.DecodeHintType.TRY_HARDER, true]])
    const reader = new ZXing.MultiFormatReader()
    reader.setHints(hints)
    // ZXing returns one barcode per image, so read overlapping horizontal strips, one barcode each
    return async (canvas) => {
      const codes = new Set()
      const strip = Math.max(40, Math.round(canvas.height / 6))
      for (let y = 0; y + strip <= canvas.height; y += Math.round(strip / 2)) {
        const part = this.frame(canvas, canvas.width, strip, null, y)
        try {
          const bitmap = new ZXing.BinaryBitmap(new ZXing.HybridBinarizer(new ZXing.HTMLCanvasElementLuminanceSource(part)))
          codes.add(reader.decode(bitmap).getText())
        } catch (_) { /* nothing in this strip */ }
        reader.reset()
      }
      return [...codes]
    }
  }

  loadZxing() {
    if (window.ZXing) return Promise.resolve(window.ZXing)
    zxingLoading ??= new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = ZXING_URL
      script.onload = () => resolve(window.ZXing)
      script.onerror = () => { zxingLoading = null; reject(new Error("ZXing didn't load")) }
      document.head.append(script)
    })
    return zxingLoading
  }

  // A canvas of the source (scaled down to `maxEdge` when given; or a horizontal strip from y)
  frame(source, width, height, maxEdge = 1600, y = null) {
    const canvas = document.createElement("canvas")
    const context = canvas.getContext("2d", { willReadFrequently: true })
    if (y !== null) {
      canvas.width = width
      canvas.height = height
      context.drawImage(source, 0, y, width, height, 0, 0, width, height)
    } else {
      const scale = maxEdge ? Math.min(1, maxEdge / Math.max(width, height)) : 1
      canvas.width = Math.round(width * scale)
      canvas.height = Math.round(height * scale)
      context.drawImage(source, 0, 0, canvas.width, canvas.height)
    }
    return canvas
  }

  // ---- The three barcodes ---------------------------------------------------------------------

  found(codes) {
    for (const raw of codes) {
      const code = raw.trim().toUpperCase().replace(/^\*|\*$/g, "")
      if (FIRST.test(code) && this.validDate(code)) this.codes.first = code
      else if (THIRD.test(code)) this.codes.third = code
      else if (SECOND.test(code)) this.codes.second = code
    }
    const done = [this.codes.first, this.codes.second, this.codes.third]
    this.tickTargets.forEach((tick, i) => {
      tick.className = done[i] ? "flex h-6 w-6 items-center justify-center rounded-full bg-green-600" : "flex h-6 w-6 items-center justify-center rounded-full border-2 border-slate-400"
      tick.innerHTML = done[i] ? '<svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5 5 9-10"/></svg>' : ""
    })
    if (this.complete() && !this.asked) {
      this.asked = true
      if (this.dialogTarget.open) this.close()
      this.lookUp()
    }
  }

  complete() { return !!(this.codes.first && this.codes.second && this.codes.third) }

  validDate(code) {
    const month = Number(code.slice(2, 4))
    const day = Number(code.slice(4, 6))
    return month >= 1 && month <= 12 && day >= 1 && day <= 31
  }

  async lookUp() {
    const query = new URLSearchParams()
    for (const code of [this.codes.first, this.codes.second, this.codes.third]) query.append("codes[]", code)
    try {
      const response = await fetch(`${this.scanUrlValue}?${query}`, { headers: { Accept: "application/json" } })
      if (!response.ok) return this.say(this.texts.not_found, "warn")
      this.scan = await response.json()
      if (this.scan.match === "already" && !this.anyway) return this.showMatch("already")
      if (!this.scan.known) return this.askBiller()
      if (this.scan.match === "similar" && !this.anyway) return this.showMatch("similar")
      this.fill()
    } catch (_) {
      this.say(this.texts.error, "warn")
    }
  }

  // ---- Already (or maybe) recorded ------------------------------------------------------------

  showMatch(kind) {
    this.messageTarget.hidden = true
    this.matchTitleTarget.textContent = this.texts[`${kind}_title`]
    this.matchLineTarget.textContent = this.texts[`${kind}_line`]
    this.matchListTarget.innerHTML = this.scan.matches
    this.alreadyTarget.hidden = kind !== "already"
    this.similarTarget.hidden = kind !== "similar"
    this.openRecordTarget.href = this.matchListTarget.querySelector("a")?.href ?? "#"
    // A similar record, opened from its card or Yes, Open It, is this bill
    this.matchListTarget.querySelectorAll("a").forEach((card) => { if (kind === "similar") card.dataset.action = "bill-scan#claim" })
    this.matchTarget.hidden = false
    this.matchTarget.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  async claim(event) {
    event.preventDefault()
    const card = event.target.closest("a[data-record-id]") ?? this.matchListTarget.querySelector("a[data-record-id]")
    if (!card) return
    const body = new URLSearchParams({ record_id: card.dataset.recordId, bill_number: this.scan.bill_number })
    const response = await fetch(this.scanUrlValue, {
      method: "PATCH", body, headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content, Accept: "application/json" }
    }).catch(() => null)
    if (!response?.ok) return this.say(this.texts.error, "warn")
    window.location.assign(card.href)
  }

  fillAnyway() {
    this.anyway = true
    this.matchTarget.hidden = true
    this.scan.known ? this.fill() : this.askBiller()
  }

  again() { this.open() }

  // ---- First time for a biller ------------------------------------------------------------------

  askBiller() {
    this.messageTarget.hidden = true
    this.askTarget.hidden = false
    this.askAmountTarget.textContent = `NT$${this.scan.amount.toLocaleString()}`
    this.askDeadlineTarget.textContent = this.scan.deadline
    this.askBillerTarget.textContent = this.scan.biller
    this.askOnceTarget.textContent = this.askOnceTarget.dataset.template.replace("%{code}", this.scan.biller)
    this.askCategoryTarget.focus()
  }

  async remember() {
    if (!this.askCategoryTarget.value) return this.askCategoryTarget.focus()
    const offset = this.askOffsetTargets.find((radio) => radio.checked)?.value ?? "0"
    const body = new URLSearchParams({ code: this.scan.biller, category_id: this.askCategoryTarget.value, deadline_offset_days: offset })
    const response = await fetch(this.rememberUrlValue, {
      method: "POST", body, headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content, Accept: "application/json" }
    }).catch(() => null)
    if (!response?.ok) return this.say(this.texts.error, "warn")
    this.askTarget.hidden = true
    this.asked = false
    this.lookUp()
  }

  // ---- Filling the form -------------------------------------------------------------------------

  fill() {
    const scan = this.scan
    this.set("record_category_id", scan.category_id, "filled")
    this.set("record_amount_required", scan.amount, "filled")
    // Months: the bill's billing month, else those of this category's latest record; either way a guess
    const [start, end] = scan.period_month ? [scan.period_month, scan.period_month] : (scan.period_months ?? [])
    this.set("record_period_year", scan.period_year, start ? "check" : "filled")
    if (start) {
      this.set("record_period_start_month", start, "check")
      this.set("record_period_end_month", end, "check")
    }
    const offsetNote = scan.deadline_offset_days > 0 ? this.texts.due_offset.replace("%{date}", scan.deadline.slice(5)).replace("%{days}", scan.deadline_offset_days) : null
    this.set("record_due_on", scan.due_on, offsetNote ? "check" : "filled", offsetNote)
    const billNumber = document.getElementById("record_bill_number")
    if (billNumber) billNumber.value = scan.bill_number

    this.messageTarget.replaceChildren()
    const title = document.createElement("strong")
    title.className = "block text-cyan-900"
    title.textContent = this.texts.filled
    const line = document.createElement("span")
    line.className = "block"
    line.textContent = this.texts.check
    this.messageTarget.append(title, line)
    if (!scan.match) {
      const clear = document.createElement("span")
      clear.className = "mt-1 block font-medium text-green-800"
      clear.textContent = this.texts.not_recorded
      this.messageTarget.append(clear)
    }
    this.show("bg-white")
    document.getElementById("record_amount_required")?.closest("section")?.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  // Sets a form field (letting other controllers react) and tags it: "filled" (cyan, from barcode) or "check" (amber, please check)
  set(id, value, kind, note = null) {
    const field = document.getElementById(id)
    if (!field || value === null || value === undefined) return
    field.value = String(value)
    field.dispatchEvent(new Event("input", { bubbles: true }))
    field.dispatchEvent(new Event("change", { bubbles: true }))
    field.classList.remove("border-cyan-400", "bg-cyan-50", "border-amber-500", "bg-amber-50", "border-2")
    field.classList.add("border-2", ...(kind === "check" ? ["border-amber-500", "bg-amber-50"] : ["border-cyan-400", "bg-cyan-50"]))
    const label = document.querySelector(`label[for="${id}"]`) ?? field.closest("fieldset")?.querySelector("legend")
    if (label && !label.querySelector("[data-scan-tag]")) {
      const tag = document.createElement("span")
      tag.dataset.scanTag = ""
      label.append(" ", tag)
    }
    const tag = label?.querySelector("[data-scan-tag]")
    if (tag) {
      tag.className = `whitespace-nowrap rounded px-1.5 text-xs font-bold ${kind === "check" ? "bg-amber-100 text-amber-900" : "bg-cyan-100 text-cyan-800"}`
      tag.textContent = kind === "check" ? this.texts.please_check : this.texts.from_barcode
    }
    field.parentElement.querySelector("[data-scan-note]")?.remove()
    if (note) {
      const p = document.createElement("p")
      p.dataset.scanNote = ""
      p.className = "mt-1 text-xs text-amber-900"
      p.textContent = note
      field.after(p)
    }
  }

  // ---- Messages ---------------------------------------------------------------------------------

  reset() {
    this.codes = {}
    this.asked = false
    this.anyway = false
    this.scan = null
    this.askTarget.hidden = true
    this.matchTarget.hidden = true
    this.messageTarget.hidden = true
    this.found([])
  }

  say(text, kind = "info") {
    this.messageTarget.textContent = text
    this.show(kind === "warn" ? "bg-amber-50 text-amber-950" : "bg-white")
  }

  show(look) {
    this.messageTarget.className = `rounded-lg px-3 py-2 text-sm ${look}`
    this.messageTarget.hidden = false
  }
}
