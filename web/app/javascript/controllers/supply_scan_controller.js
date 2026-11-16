import { Controller } from "@hotwired/stimulus"

// New → Scan product barcode, and New → Add a receipt › Printed receipt. Reads in the browser only, from the camera (a webcam on a computer), a
// photo you choose, drop or paste, at a few sizes and turns: product barcodes (EAN-13/JAN, EAN-8, UPC)
// and a Taiwan e-invoice's two QR codes. The browser's own BarcodeDetector when it has one, else ZXing,
// loaded only then. The photo never leaves the device: a barcode number goes to supplies/scans#barcode,
// the two QR texts to supplies/receipts#new (the review screen).
const ZXING_URL = "/vendor/zxing-0.21.3.min.js"
const PRODUCT_FORMATS = ["ean_13", "ean_8", "upc_a", "upc_e"]
const LEFT_QR = /^[A-Z]{2}\d{8}\d{7}\d{4}[0-9a-fA-F]{16}\d{16}/
let zxingLoading = null

export default class extends Controller {
  static targets = ["video", "camera", "photo", "message", "code", "left", "right", "receiptForm", "tickLeft", "tickRight", "labelLeft", "labelRight", "qrCount", "light", "drop"]
  static values = { mode: String, barcodeUrl: String, texts: Object }

  connect() {
    this.paste = (event) => {
      const file = [...(event.clipboardData?.files || [])].find((f) => f.type.startsWith("image/"))
      if (file) { event.preventDefault(); this.readFile(file) }
    }
    document.addEventListener("paste", this.paste)
  }

  disconnect() {
    document.removeEventListener("paste", this.paste)
    this.stop()
  }

  // ---- Camera -------------------------------------------------------------------------------

  async start() {
    this.reset()
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment", width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false })
    } catch (_) {
      return this.say(this.textsValue.no_camera, "warn")
    }
    this.cameraTarget.hidden = false
    this.videoTarget.srcObject = this.stream
    await this.videoTarget.play().catch(() => {})
    if (this.hasLightTarget) this.lightTarget.hidden = !this.stream.getVideoTracks()[0].getCapabilities?.().torch
    this.decode = await this.decoder()
    this.say(this.modeValue === "receipt" ? this.textsValue.point_receipt : this.textsValue.point_barcode)
    this.loop()
  }

  loop() {
    if (!this.stream) return
    const video = this.videoTarget
    const next = () => { this.timer = setTimeout(() => this.loop(), 200) }
    if (!video.videoWidth) return next()
    this.decode(this.frame(video, video.videoWidth, video.videoHeight, 1600)).then((codes) => this.found(codes)).finally(next)
  }

  stop() {
    clearTimeout(this.timer)
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
    if (this.hasCameraTarget) this.cameraTarget.hidden = true
  }

  toggleLight() {
    const track = this.stream?.getVideoTracks()[0]
    if (!track) return
    this.lit = !this.lit
    track.applyConstraints({ advanced: [{ torch: this.lit }] }).catch(() => {})
  }

  // ---- Photos -------------------------------------------------------------------------------

  choose() { this.photoTarget.click() }

  readPhoto() {
    const file = this.photoTarget.files[0]
    if (file) this.readFile(file)
    this.photoTarget.value = ""
  }

  dragOver(event) { event.preventDefault(); this.dropTarget.classList.add("bg-blue-50") }
  dragLeave() { this.dropTarget.classList.remove("bg-blue-50") }

  drop(event) {
    event.preventDefault()
    this.dragLeave()
    const file = [...event.dataTransfer.files].find((f) => f.type.startsWith("image/") || /\.hei[cf]$/i.test(f.name))
    if (file) this.readFile(file)
  }

  async readFile(file) {
    this.stop()
    this.reset()
    this.say(this.textsValue.reading)
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
      const decode = await this.decoder()
      // A few sizes and quarter turns: a small barcode in a big photo, or a receipt shot sideways
      for (const edge of [1600, 2400, 1000]) {
        for (const turn of [0, 90]) {
          this.found(await decode(this.frame(bitmap, bitmap.width, bitmap.height, edge, turn)))
          if (this.done) return
        }
      }
      this.say(this.modeValue === "receipt" && (this.left || this.right) ? this.textsValue.need_both : this.textsValue.not_found, "warn")
    } catch (_) {
      this.say(this.textsValue.not_found, "warn")
    }
  }

  // ---- Typing the number ----------------------------------------------------------------------

  typed(event) {
    event.preventDefault()
    const code = this.codeTarget.value.replace(/\D/g, "")
    if (!this.validProduct(code)) return this.say(this.textsValue.bad_number, "warn")
    this.goBarcode(code)
  }

  // ---- What was read ----------------------------------------------------------------------------

  found(codes) {
    if (this.done) return
    for (const raw of codes) {
      const text = raw.trim()
      if (this.modeValue === "barcode") {
        const code = text.replace(/\D/g, "")
        if (/^\d+$/.test(text) && this.validProduct(code)) return this.goBarcode(code)
        if (LEFT_QR.test(text)) this.say(this.textsValue.is_receipt, "warn")
      } else if (text.startsWith("**")) {
        this.right = text
      } else if (LEFT_QR.test(text)) {
        this.left = text
      } else if (/^\d{8,14}$/.test(text)) {
        this.say(this.textsValue.is_barcode, "warn")
      } else {
        this.say(this.textsValue.not_einvoice, "warn")
      }
    }
    if (this.modeValue === "receipt") this.receiptProgress()
  }

  // Progress, not a choice: each QR code's square turns green when it's read, with "1 of 2 read"
  receiptProgress() {
    this.tick(this.tickLeftTarget, this.labelLeftTarget, this.textsValue.left_qr, this.left)
    this.tick(this.tickRightTarget, this.labelRightTarget, this.textsValue.right_qr, this.right)
    this.qrCountTarget.textContent = this.textsValue.qr_count.replace("%{count}", [this.left, this.right].filter(Boolean).length)
    if (this.left && this.right) {
      this.done = true
      this.stop()
      this.leftTarget.value = this.left
      this.rightTarget.value = this.right
      this.say(this.textsValue.reading_receipt)
      this.receiptFormTarget.requestSubmit()
    } else if (this.left || this.right) {
      this.say(this.textsValue.need_both)
    }
  }

  tick(box, label, name, ok) {
    box.className = ok
      ? "flex h-14 w-14 items-center justify-center rounded-lg border-[3px] border-green-600 bg-green-100 text-2xl font-extrabold text-green-800"
      : "flex h-14 w-14 items-center justify-center rounded-lg border-[3px] border-dashed border-gray-400 text-xl text-gray-400"
    box.textContent = ok ? "✓" : "▦"
    label.className = ok ? "text-xs font-bold text-green-800" : "text-xs font-semibold text-gray-600"
    label.textContent = `${name} · ${ok ? this.textsValue.qr_read : this.textsValue.qr_needed}`
  }

  goBarcode(code) {
    this.done = true
    this.stop()
    this.say(this.textsValue.looking_up)
    const url = new URL(this.barcodeUrlValue, window.location.origin)
    url.searchParams.set("code", code)
    window.Turbo ? window.Turbo.visit(url.toString()) : window.location.assign(url)
  }

  // EAN-13/JAN, EAN-8, UPC-A (12) with a correct check digit; UPC-E (8) passes the EAN-8 check form
  validProduct(code) {
    if (![8, 12, 13, 14].includes(code.length)) return false
    const digits = code.split("").map(Number)
    const check = digits.pop()
    const sum = digits.reverse().reduce((total, digit, i) => total + digit * (i % 2 === 0 ? 3 : 1), 0)
    return (10 - (sum % 10)) % 10 === check
  }

  reset() {
    this.done = false
    if (this.modeValue === "receipt") { this.left = this.right = null; this.receiptProgress() }
  }

  say(text, tone) {
    this.messageTarget.hidden = false
    this.messageTarget.textContent = text
    this.messageTarget.className = `rounded-lg px-3 py-2 text-sm font-medium ${tone === "warn" ? "bg-amber-50 text-amber-900" : "bg-blue-50 text-blue-900"}`
  }

  // ---- Decoders -----------------------------------------------------------------------------------

  async decoder() {
    const wanted = this.modeValue === "receipt" ? ["qr_code"] : PRODUCT_FORMATS.concat("qr_code")
    if ("BarcodeDetector" in window) {
      const supported = await window.BarcodeDetector.getSupportedFormats().catch(() => [])
      const formats = wanted.filter((f) => supported.includes(f))
      if (formats.length === wanted.length) {
        const detector = new window.BarcodeDetector({ formats })
        return async (canvas) => (await detector.detect(canvas).catch(() => [])).map((code) => code.rawValue)
      }
    }
    const ZXing = await this.loadZxing()
    const F = ZXing.BarcodeFormat
    const formats = this.modeValue === "receipt" ? [F.QR_CODE] : [F.EAN_13, F.EAN_8, F.UPC_A, F.UPC_E, F.QR_CODE]
    const reader = new ZXing.MultiFormatReader()
    reader.setHints(new Map([[ZXing.DecodeHintType.POSSIBLE_FORMATS, formats], [ZXing.DecodeHintType.TRY_HARDER, true]]))
    const readOne = (canvas) => {
      try {
        return reader.decode(new ZXing.BinaryBitmap(new ZXing.HybridBinarizer(new ZXing.HTMLCanvasElementLuminanceSource(canvas)))).getText()
      } catch (_) { return null } finally { reader.reset() }
    }
    // ZXing reads one code per image: a receipt's two QR codes sit side by side, so read each half too
    return async (canvas) => {
      const codes = new Set([readOne(canvas)])
      if (this.modeValue === "receipt") {
        const half = Math.round(canvas.width / 2)
        codes.add(readOne(this.crop(canvas, 0, half)))
        codes.add(readOne(this.crop(canvas, half, canvas.width - half)))
      }
      codes.delete(null)
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

  frame(source, width, height, maxEdge, turn = 0) {
    const canvas = document.createElement("canvas")
    const context = canvas.getContext("2d", { willReadFrequently: true })
    const scale = Math.min(1, maxEdge / Math.max(width, height))
    const w = Math.round(width * scale)
    const h = Math.round(height * scale)
    canvas.width = turn ? h : w
    canvas.height = turn ? w : h
    if (turn) { context.translate(h, 0); context.rotate(Math.PI / 2) }
    context.drawImage(source, 0, 0, w, h)
    return canvas
  }

  crop(source, x, width) {
    const canvas = document.createElement("canvas")
    canvas.width = width
    canvas.height = source.height
    canvas.getContext("2d", { willReadFrequently: true }).drawImage(source, x, 0, width, source.height, 0, 0, width, source.height)
    return canvas
  }
}
