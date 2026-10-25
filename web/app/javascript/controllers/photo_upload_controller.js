import { Controller } from "@hotwired/stimulus"

// Two-step photo form: ① Choose Photos, ② Upload (disabled until photos are chosen). After choosing it
// shows how many were picked with small previews. Picked or captured photos are resized to ≤2000px
// JPEG before upload (PRD §7), so 10–20 MB camera files fit the limit and upload fast on mobile data.
// If a file can't be decoded here (e.g. HEIC on some devices) the original is sent; the server
// sanitizer is the authority either way.
export default class extends Controller {
  static targets = ["input", "submit", "status", "summary", "count", "previews", "label", "stepOne", "stepTwo"]
  static values = { maxEdge: { type: Number, default: 2000 }, working: String,
                    chosenOne: String, chosenOther: String, uploadOne: String, uploadOther: String }

  connect() {
    this.noneText = this.statusTarget.textContent
    this.uploadText = this.labelTarget.textContent
  }

  disconnect() { this.clearPreviews() }

  async resize() {
    const files = Array.from(this.inputTarget.files)
    this.show(files)
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

  // Step ① done: the count, small previews, step ② lit up and saying how many it will upload
  show(files) {
    const chosen = files.length > 0
    const n = files.length
    this.element.toggleAttribute("data-chosen", chosen)
    this.statusTarget.hidden = chosen
    this.summaryTarget.hidden = !chosen
    this.previewsTarget.hidden = !chosen
    this.countTarget.textContent = this.plural(n, this.chosenOneValue, this.chosenOtherValue)
    this.labelTarget.textContent = chosen ? this.plural(n, this.uploadOneValue, this.uploadOtherValue) : this.uploadText
    this.statusTarget.textContent = this.noneText
    this.stepOneTarget.classList.toggle("bg-green-700", chosen)
    this.stepOneTarget.classList.toggle("bg-blue-700", !chosen)
    this.stepTwoTarget.classList.toggle("bg-blue-700", chosen)
    this.stepTwoTarget.classList.toggle("text-white", chosen)
    this.stepTwoTarget.classList.toggle("bg-gray-300", !chosen)
    this.submitTarget.disabled = !chosen
    this.clearPreviews()
    for (const file of files.slice(0, 10)) {
      const img = document.createElement("img")
      img.src = URL.createObjectURL(file)
      img.alt = file.name
      img.className = "h-16 w-16 rounded border object-cover"
      this.previewsTarget.append(img)
    }
  }

  plural(n, one, other) { return n === 1 ? one : other.replace("%{count}", n) }

  clearPreviews() {
    if (!this.hasPreviewsTarget) return
    this.previewsTarget.querySelectorAll("img").forEach((img) => URL.revokeObjectURL(img.src))
    this.previewsTarget.replaceChildren()
  }

  // While shrinking: Upload waits and the status line says so
  busy(on) {
    this.submitTarget.disabled = on
    this.statusTarget.hidden = !on
    this.statusTarget.textContent = on ? this.workingValue : this.noneText
  }
}
