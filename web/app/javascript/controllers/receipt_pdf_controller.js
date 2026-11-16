import { Controller } from "@hotwired/stimulus"

// Add a receipt › Invoice PDF. Reads each PDF (發票明細) in the browser with pdf.js, loaded only here
// from /vendor: the file never leaves the device. What goes to the review screen
// (supplies/receipts#new, read by Supplies::InvoicePdfParser) is each PDF's name and its text pieces
// with where they sit on the page: [{ s, x, y (from the top), w, h }].
export default class extends Controller {
  static targets = ["drop", "input", "list", "form", "fields", "submit"]
  static values = { base: String, max: Number, texts: Object }

  connect() {
    this.pdfs = []
  }

  choose() { this.inputTarget.click() }

  picked() {
    this.add([...this.inputTarget.files])
    this.inputTarget.value = ""
  }

  dragOver(event) { event.preventDefault(); this.dropTarget.classList.add("bg-blue-50") }
  dragLeave() { this.dropTarget.classList.remove("bg-blue-50") }

  drop(event) {
    event.preventDefault()
    this.dragLeave()
    this.add([...event.dataTransfer.files])
  }

  async add(files) {
    for (const file of files.filter((f) => f.type === "application/pdf" || /\.pdf$/i.test(f.name))) {
      if (this.pdfs.length >= this.maxValue) { this.row({ name: file.name }, this.textsValue.too_many, "warn"); break }
      const pdf = { name: file.name, words: [], id: crypto.randomUUID?.() || String(Math.random()) }
      this.pdfs.push(pdf)
      const row = this.row(pdf, this.textsValue.reading)
      try {
        pdf.words = await this.read(file)
        pdf.pages = this.pages
        if (pdf.words.length) this.status(row, this.textsValue.read.replace("%{count}", pdf.pages), "ok")
        else this.status(row, this.textsValue.no_text, "bad")
      } catch (error) {
        this.status(row, error?.name === "PasswordException" ? this.textsValue.password : this.textsValue.cant_open, "bad")
      }
      this.sync()
    }
  }

  remove(event) {
    const id = event.currentTarget.dataset.id
    this.pdfs = this.pdfs.filter((pdf) => pdf.id !== id)
    event.currentTarget.closest("li").remove()
    this.sync()
  }

  // ---- Reading -------------------------------------------------------------------------------------

  async read(file) {
    const pdfjs = await this.pdfjs()
    const task = pdfjs.getDocument({ data: await file.arrayBuffer(), cMapUrl: `${this.baseValue}cmaps/`, cMapPacked: true, isEvalSupported: false })
    // Some stores lock the PDF (often with an ID or phone number): ask once, else give up on it
    task.onPassword = (update, reason) => {
      const answer = window.prompt(reason === pdfjs.PasswordResponses.INCORRECT_PASSWORD ? this.textsValue.password_wrong : this.textsValue.password_ask.replace("%{name}", file.name))
      answer ? update(answer) : task.destroy()
    }
    const doc = await task.promise
    this.pages = doc.numPages
    const words = []
    for (let n = 1; n <= Math.min(doc.numPages, 10); n++) {
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
    this.loading ??= import(`${this.baseValue}pdf.min.mjs`).then((pdfjs) => {
      pdfjs.GlobalWorkerOptions.workerSrc = `${this.baseValue}pdf.worker.min.mjs`
      return pdfjs
    })
    return this.loading
  }

  // ---- The list and the form -----------------------------------------------------------------------

  row(pdf, text, tone) {
    const li = document.createElement("li")
    li.className = "flex flex-wrap items-center justify-between gap-2 rounded-xl border border-gray-300 bg-white px-3 py-2 text-sm"
    const name = document.createElement("span")
    name.className = "min-w-0 truncate font-medium"
    name.textContent = `📄 ${pdf.name}`
    const right = document.createElement("span")
    right.className = "flex items-center gap-2"
    const status = document.createElement("span")
    status.dataset.status = ""
    right.append(status)
    if (pdf.id) {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "btn-press cursor-pointer rounded-lg bg-white px-2 py-0.5 text-xs font-medium text-gray-900"
      button.textContent = this.textsValue.remove
      button.dataset.id = pdf.id
      button.dataset.action = "receipt-pdf#remove"
      right.append(button)
    }
    li.append(name, right)
    this.listTarget.append(li)
    this.status(li, text, tone)
    return li
  }

  status(li, text, tone) {
    const status = li.querySelector("[data-status]")
    status.textContent = text
    status.className = `rounded-full px-2 py-0.5 text-xs font-bold ${{ ok: "bg-green-100 text-green-800", bad: "bg-red-100 text-red-800", warn: "bg-amber-100 text-amber-900" }[tone] || "bg-gray-100 text-gray-700"}`
  }

  // Hidden fields for every PDF read so far (unreadable ones too: the review lists them under Not included)
  sync() {
    this.fieldsTarget.replaceChildren(...this.pdfs.flatMap((pdf, index) => [
      this.hidden(`pdfs[${index}][name]`, pdf.name),
      this.hidden(`pdfs[${index}][words]`, JSON.stringify(pdf.words))
    ]))
    this.submitTarget.disabled = !this.pdfs.some((pdf) => pdf.words.length)
  }

  hidden(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    return input
  }
}
