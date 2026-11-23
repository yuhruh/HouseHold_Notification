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
//
// Choose Bill PDF (or a PDF dropped on the card): pdf.js, loaded only then from /vendor, reads the PDF on
// the device (a locked one asks for its password in the card; it's used only here). Its text pieces go to
// bill_pdfs#create (Records::BillPdfParser), and the answer goes through the same steps: already / similar,
// a biller seen for the first time asks once (its code "T" + its tax ID), then the form is filled, tagged
// "from PDF" or "please check". A bill the parser hasn't learned comes back read by its labels: every
// field "please check", no category. A bill paid by itself (定期付款) shows a note in Payment Details.
//
// Use a Photo: the barcodes first. A photo without all 3 (a bill with no 超商代收 barcodes, or a photo of
// its top half) is read for its text on the device with Tesseract (繁體中文 + English, under /vendor, loaded
// only then), and its words go to bill_pdfs#create like a PDF's. The photo is never uploaded. A photo can be
// misread, so every number and date it fills is "please check"; only the title and category (from the
// bill's 統一編號, matched exactly) are "from photo".
const ZXING_URL = "/vendor/zxing-0.21.3.min.js"
const TESSERACT = "/vendor/tesseract-5.1.1"
const FIRST = /^(\d{6})([0-9A-Z]{3})$/
const THIRD = /^\d{4}[0-9A-Z]{2}\d{9}$/
const SECOND = /^[0-9A-Z]{6,20}$/
let zxingLoading = null
let ocrLoading = null

export default class extends Controller {
  static targets = ["card", "message", "photo", "dialog", "video", "tick", "light", "lightSpacer", "texts",
                    "ask", "askAmount", "askDeadline", "askBiller", "askOnce", "askCategory", "askOffset",
                    "match", "matchTitle", "matchLine", "matchList", "already", "similar", "openRecord",
                    "pdf", "drop", "lock", "lockName", "lockMessage", "lockInput", "readTitle", "askDeadlineLabel",
                    "askBillerLabel", "askOffsetBox", "againButton", "autopay"]
  static values = { scanUrl: String, rememberUrl: String, pdfUrl: String, pdfBase: String }

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

  // The barcodes when all 3 are there; otherwise the bill's text
  async readPhoto() {
    const file = this.photoTarget.files[0]
    this.photoTarget.value = ""
    if (!file) return
    this.reset()
    this.say(this.texts.reading)
    let bitmap
    try {
      bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
    } catch (_) {
      return this.say(this.texts.photo_unreadable, "warn")
    }
    try {
      const decode = await this.decoder()
      this.found(await decode(this.frame(bitmap, bitmap.width, bitmap.height, 2400)))
    } catch (_) { /* no barcode reader: read the text */ }
    if (!this.complete()) this.readText(bitmap)
  }

  // ---- A photo's text (no barcodes) ---------------------------------------------------------------

  async readText(bitmap) {
    this.reset()
    this.source = "photo"
    this.say(ocrLoading ? this.texts.reading_text : this.texts.reading_text_first)
    let worker
    try {
      worker = await this.ocr()
    } catch (_) {
      return this.say(this.texts.ocr_unavailable, "warn")
    }
    this.say(this.texts.reading_text)
    try {
      const { data } = await worker.recognize(this.frame(bitmap, bitmap.width, bitmap.height, 2400))
      this.words = this.photoWords(data)
    } catch (_) {
      return this.say(this.texts.photo_unreadable, "warn")
    }
    if (!this.words.length) return this.say(this.texts.photo_unreadable, "warn")
    this.lookUp()
  }

  // Tesseract's words in the PDF's shape, [{ s, x, y, w, h }], so Records::BillPdfParser reads them the
  // same way: every word of a line gets the line's place and letter height (a photo taken at a slight
  // angle still reads as lines), and the page is scaled so a line is about 10 high, as in a PDF (pt)
  photoWords(data) {
    const median = (values) => values.sort((a, b) => a - b)[Math.floor(values.length / 2)]
    const lines = (data?.lines || []).map((line) => {
      const words = (line.words || []).filter((word) => word.confidence >= 30 && word.text?.trim())
      if (!words.length) return null
      const h = median(words.map((word) => word.bbox.y1 - word.bbox.y0))
      const middle = median(words.map((word) => (word.bbox.y0 + word.bbox.y1) / 2))
      return { words, h, y: middle - h / 2 }
    }).filter((line) => line && line.h > 0)
    if (!lines.length) return []
    const scale = 10 / median(lines.map((line) => line.h))
    const round = (v) => Math.round(v * scale * 10) / 10
    return lines.flatMap((line) => line.words.map((word) => ({
      s: word.text.trim(), x: round(word.bbox.x0), y: round(line.y), w: round(word.bbox.x1 - word.bbox.x0), h: round(line.h)
    })))
  }

  // One reader per page visit, kept for the next photo
  ocr() {
    ocrLoading ??= this.loadTesseract().then((Tesseract) => Tesseract.createWorker(["chi_tra", "eng"], 1, {
      workerPath: `${TESSERACT}/worker.min.js`, corePath: `${TESSERACT}/core`, langPath: `${TESSERACT}/lang`, workerBlobURL: false, gzip: true
    })).catch((error) => { ocrLoading = null; throw error })
    return ocrLoading
  }

  loadTesseract() {
    if (window.Tesseract) return Promise.resolve(window.Tesseract)
    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = `${TESSERACT}/tesseract.min.js`
      script.onload = () => resolve(window.Tesseract)
      script.onerror = () => reject(new Error("Tesseract didn't load"))
      document.head.append(script)
    })
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

  // ---- A bill PDF ------------------------------------------------------------------------------

  choosePdf() { this.pdfTarget.click() }

  readPdf() {
    const file = this.pdfTarget.files[0]
    this.pdfTarget.value = ""
    if (file) this.loadPdf(file)
  }

  dragOver(event) {
    if (!event.dataTransfer?.types?.includes("Files")) return
    event.preventDefault()
    this.dropTarget.classList.add("bg-cyan-100", "border-solid")
  }

  dragLeave() { this.dropTarget.classList.remove("bg-cyan-100", "border-solid") }

  drop(event) {
    if (!event.dataTransfer?.files?.length) return
    event.preventDefault()
    this.dragLeave()
    const file = [...event.dataTransfer.files].find((f) => f.type === "application/pdf" || /\.pdf$/i.test(f.name))
    if (file) this.loadPdf(file)
  }

  async loadPdf(file) {
    this.reset()
    this.source = "pdf"
    this.say(this.texts.reading_pdf)
    try {
      this.words = await this.pdfWords(file)
    } catch (_) {
      this.lockTarget.hidden = true
      return this.cancelled ? (this.messageTarget.hidden = true) : this.say(this.texts.pdf_cant_open, "warn")
    }
    if (!this.words.length) return this.say(this.texts.pdf_no_text, "warn")
    this.lookUp()
  }

  // The PDF's text pieces with where each sits on the page: [{ s, x, y (from the top), w, h }]
  async pdfWords(file) {
    const pdfjs = await this.pdfjs()
    const task = pdfjs.getDocument({ data: await file.arrayBuffer(), cMapUrl: `${this.pdfBaseValue}cmaps/`, cMapPacked: true, isEvalSupported: false })
    task.onPassword = (update, reason) => {
      this.askPassword(file.name, reason === pdfjs.PasswordResponses.INCORRECT_PASSWORD)
        .then((answer) => (answer === null ? task.destroy() : update(answer)))
    }
    const doc = await task.promise
    this.lockTarget.hidden = true
    const words = []
    for (let n = 1; n <= Math.min(doc.numPages, 3); n++) {
      const page = await doc.getPage(n)
      const view = page.getViewport({ scale: 1 })
      for (const item of (await page.getTextContent()).items) {
        if (!item.str?.trim()) continue
        const [x, y] = view.convertToViewportPoint(item.transform[4], item.transform[5])
        const round = (v) => Math.round(v * 10) / 10
        words.push({ s: item.str, x: round(x), y: round(y - item.height + (n - 1) * 10000), w: round(item.width), h: round(item.height) })
      }
    }
    doc.destroy()
    return words
  }

  pdfjs() {
    this.pdfLoading ??= import(`${this.pdfBaseValue}pdf.min.mjs`).then((pdfjs) => {
      pdfjs.GlobalWorkerOptions.workerSrc = `${this.pdfBaseValue}pdf.worker.min.mjs`
      return pdfjs
    }).catch((error) => { this.pdfLoading = null; throw error })
    return this.pdfLoading
  }

  // A locked PDF: asks in the card, resolves with the password, or null for Cancel
  askPassword(name, wrong) {
    this.messageTarget.hidden = true
    this.lockNameTarget.textContent = name
    this.lockMessageTarget.textContent = wrong ? this.texts.password_wrong : this.texts.password_ask
    this.lockInputTarget.value = ""
    this.lockTarget.hidden = false
    this.lockInputTarget.focus()
    return new Promise((resolve) => { this.unlock = resolve })
  }

  openPdf() {
    if (!this.lockInputTarget.value) return this.lockInputTarget.focus()
    this.lockTarget.hidden = true
    this.say(this.texts.reading_pdf)
    this.unlock?.(this.lockInputTarget.value)
    this.lockInputTarget.value = ""
    this.unlock = null
  }

  cancelPdf() {
    this.lockTarget.hidden = true
    this.cancelled = true
    this.unlock?.(null)
    this.unlock = null
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
    try {
      const response = this.byText() ? await this.lookUpWords() : await this.lookUpCodes()
      if (!response.ok) return this.say(this.texts[{ pdf: "pdf_unreadable", photo: "photo_unreadable" }[this.source] ?? "not_found"], "warn")
      this.scan = await response.json()
      if (this.scan.match === "already" && !this.anyway) return this.showMatch("already")
      if (!this.scan.known) return this.askBiller()
      if (this.scan.match === "similar" && !this.anyway) return this.showMatch("similar")
      this.fill()
    } catch (_) {
      this.say(this.texts.error, "warn")
    }
  }

  lookUpCodes() {
    const query = new URLSearchParams()
    for (const code of [this.codes.first, this.codes.second, this.codes.third]) query.append("codes[]", code)
    return fetch(`${this.scanUrlValue}?${query}`, { headers: { Accept: "application/json" } })
  }

  lookUpWords() {
    return fetch(this.pdfUrlValue, {
      method: "POST", body: JSON.stringify({ words: JSON.stringify(this.words) }),
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
    })
  }

  // Read from words (a PDF, or a photo's text), not barcodes
  byText() { return this.source !== "barcode" }

  photo() { return this.source === "photo" }

  // ---- Already (or maybe) recorded ------------------------------------------------------------

  showMatch(kind) {
    this.messageTarget.hidden = true
    this.readTitleTargets.forEach((title) => { title.textContent = this.readTitle() })
    this.againButtonTarget.textContent = this.texts[{ pdf: "choose_another", photo: "take_another" }[this.source] ?? "scan_another"]
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

  again() {
    if (this.source === "pdf") return this.choosePdf()
    if (this.photo()) return this.photoTarget.click()
    this.open()
  }

  // "All 3 barcodes read", or "Bill read: 中華電信"
  readTitle() { return this.byText() ? this.texts.bill_read.replace("%{name}", this.scan.biller_name || (this.photo() ? this.texts.the_photo : "PDF")) : this.texts.all_read }

  // ---- First time for a biller ------------------------------------------------------------------

  askBiller() {
    this.messageTarget.hidden = true
    this.askTarget.hidden = false
    const pdf = this.byText()
    const biller = pdf ? this.scan.biller_name : this.scan.biller
    this.readTitleTargets.forEach((title) => { title.textContent = this.readTitle() })
    this.askAmountTarget.textContent = `NT$${this.scan.amount.toLocaleString()}`
    this.askDeadlineLabelTarget.textContent = pdf ? this.texts.due : this.texts.deadline
    this.askDeadlineTarget.textContent = this.scan.deadline
    this.askBillerLabelTarget.textContent = pdf ? this.texts.biller_name : this.texts.biller
    this.askBillerTarget.textContent = biller
    this.askOnceTarget.textContent = this.askOnceTarget.dataset.template.replace("%{code}", biller)
    // A bill's printed due date is the due date; only barcodes ask what their deadline means
    this.askOffsetBoxTarget.hidden = pdf
    if (pdf && this.scan.suggested_category_id && !this.askCategoryTarget.value) this.askCategoryTarget.value = String(this.scan.suggested_category_id)
    this.askCategoryTarget.focus()
  }

  async remember() {
    if (!this.askCategoryTarget.value) return this.askCategoryTarget.focus()
    const offset = this.byText() ? "0" : (this.askOffsetTargets.find((radio) => radio.checked)?.value ?? "0")
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
    const pdf = this.byText()
    // Printed on the bill: "from barcode" / "from PDF"; a bill read only by its labels, or any number or
    // date read from a photo: "please check"
    const sure = pdf && (!scan.learned || this.photo()) ? "check" : "filled"
    this.set("record_category_id", scan.category_id, "filled")
    if (pdf) {
      this.set("record_title", scan.title, "filled")
      this.set("record_details", scan.details, "check")
    }
    this.set("record_amount_required", scan.amount, sure)
    // Months: the bill's billing month or period, else those of this category's latest record; a guess
    const [start, end] = scan.period_month ? [scan.period_month, scan.period_month] : (scan.period_months ?? [])
    this.set("record_period_year", scan.period_year, start || sure === "check" ? "check" : "filled")
    if (start) {
      const said = scan.period_note && this.texts.period_note.replace("%{from}", scan.period_note[0]).replace("%{to}", scan.period_note[1])
      this.set("record_period_start_month", start, "check")
      this.set("record_period_end_month", end, "check", said)
    }
    const offsetNote = scan.deadline_offset_days > 0 ? this.texts.due_offset.replace("%{date}", scan.deadline.slice(5)).replace("%{days}", scan.deadline_offset_days) : null
    this.set("record_due_on", scan.due_on, offsetNote ? "check" : sure, offsetNote)
    const billNumber = document.getElementById("record_bill_number")
    if (billNumber) billNumber.value = scan.bill_number ?? ""
    if (this.hasAutopayTarget) {
      this.autopayTarget.textContent = scan.autopay ? this.texts.autopay.replace("%{way}", scan.autopay) : ""
      this.autopayTarget.hidden = !scan.autopay
    }

    this.messageTarget.replaceChildren()
    const title = document.createElement("strong")
    title.className = "block text-cyan-900"
    title.textContent = !pdf ? this.texts.filled : (!scan.learned ? this.texts.by_labels : (this.photo() ? this.texts.filled_photo : this.texts.filled_pdf))
    const line = document.createElement("span")
    line.className = "block"
    line.textContent = pdf && !scan.learned ? this.texts.by_labels_line : (this.photo() ? this.texts.filled_photo_line : this.texts.check)
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
      tag.textContent = kind === "check" ? this.texts.please_check : this.texts[{ pdf: "from_pdf", photo: "from_photo" }[this.source] ?? "from_barcode"]
    }
    field.parentElement.querySelector("[data-scan-note]")?.remove()
    if (note) {
      const p = document.createElement("p")
      p.dataset.scanNote = ""
      p.className = "col-span-full mt-1 text-xs text-amber-900"
      p.textContent = note
      field.after(p)
    }
  }

  // ---- Messages ---------------------------------------------------------------------------------

  reset() {
    this.source = "barcode"
    this.words = null
    this.cancelled = false
    this.unlock?.(null)
    this.unlock = null
    this.lockTarget.hidden = true
    if (this.hasAutopayTarget) this.autopayTarget.hidden = true
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
