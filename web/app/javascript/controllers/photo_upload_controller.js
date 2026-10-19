import { Controller } from "@hotwired/stimulus"

// Resizes picked or captured photos to ≤2000px JPEG before upload (PRD §7), so 10–20 MB camera
// files fit the limit and upload fast on mobile data. If a file can't be decoded here (e.g. HEIC
// on some devices) the original is sent; the server sanitizer is the authority either way.
export default class extends Controller {
  static targets = ["input", "submit", "status"]
  static values = { maxEdge: { type: Number, default: 2000 }, working: String }

  async resize() {
    const files = Array.from(this.inputTarget.files)
    if (files.length === 0) return
    this.busy(true)
    const transfer = new DataTransfer()
    for (const file of files) transfer.items.add(await this.shrink(file))
    this.inputTarget.files = transfer.files
    this.busy(false)
  }

  async shrink(file) {
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
      const scale = Math.min(1, this.maxEdgeValue / Math.max(bitmap.width, bitmap.height))
      if (scale === 1 && file.type === "image/jpeg") return file
      const canvas = document.createElement("canvas")
      canvas.width = Math.round(bitmap.width * scale)
      canvas.height = Math.round(bitmap.height * scale)
      canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85))
      if (!blob) return file
      return new File([blob], file.name.replace(/\.[^.]+$/, "") + ".jpg", { type: "image/jpeg" })
    } catch (_) {
      return file
    }
  }

  busy(on) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = on
    if (this.hasStatusTarget) this.statusTarget.textContent = on ? this.workingValue : ""
  }
}
