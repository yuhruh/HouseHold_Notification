import { Controller } from "@hotwired/stimulus"

// Two-step photo form: ① Take Photo (camera) or Choose Files, ② Upload (disabled until there is something
// to upload). What each one picks joins one list, shown as a count and small previews, each with ✕ to take
// it out; the buttons then read Take Another and Add Files. The list is put on the Choose Files field, the
// one that is submitted. A photo that looks the same as one already on the record or already in the list
// (Photos::Fingerprint, computed the same way here) is tagged "Already added" and left out of the upload;
// the server checks again either way. Picked or captured photos are resized to ≤2000px JPEG before upload
// (PRD §7), so 10–20 MB camera files fit the limit and upload fast on mobile data. If a file can't be
// decoded here (e.g. HEIC on some devices) the original is sent; the server sanitizer is the authority
// either way.
export default class extends Controller {
  static targets = ["input", "camera", "cameraLabel", "filesLabel", "submit", "status", "count", "previews", "label", "stepOne", "stepTwo", "duplicates"]
  static values = { maxEdge: { type: Number, default: 2000 }, working: String, existing: Array, threshold: { type: Number, default: 5 }, margin: { type: Number, default: 6 },
                    chosenOne: String, chosenOther: String, uploadOne: String, uploadOther: String,
                    duplicateOne: String, duplicateOther: String, tag: String, takeAnother: String, addFiles: String, remove: String }

  connect() {
    this.noneText = this.statusTarget.textContent
    this.uploadText = this.labelTarget.textContent
    this.cameraText = this.hasCameraLabelTarget ? this.cameraLabelTarget.textContent : ""
    this.filesText = this.filesLabelTarget.textContent
    this.items = [] // { file (shrunk, uploaded unless a duplicate), original (previewed), print, duplicate }
  }

  disconnect() { this.clearPreviews() }

  // A field picked something: add it to the list (a field cleared by a cancelled picker adds nothing)
  async add(event) {
    const field = event.target
    const files = Array.from(field.files).filter((file) => !this.items.some((item) => item.file === file))
    if (files.length > 0) {
      this.busy(true)
      for (const original of files) {
        const bitmap = await createImageBitmap(original, { imageOrientation: "from-image" }).catch(() => null)
        const print = bitmap && this.fingerprint(bitmap)
        const seen = this.existingValue.concat(this.items.filter((item) => !item.duplicate && item.print).map((item) => item.print))
        const duplicate = print !== null && seen.some((other) => this.same(other, print))
        const file = duplicate ? original : await this.shrink(original, bitmap)
        this.items.push({ file, original, print, duplicate })
      }
      this.busy(false)
    }
    if (field !== this.inputTarget) field.value = ""
    this.sync()
  }

  // ✕ on a preview: out of the list; a repeat it was hiding counts again
  drop(event) {
    this.items.splice(Number(event.currentTarget.dataset.index), 1)
    const seen = this.existingValue.slice()
    for (const item of this.items) {
      item.duplicate = item.print !== null && seen.some((other) => this.same(other, item.print))
      if (item.print && !item.duplicate) seen.push(item.print)
    }
    Promise.all(this.items.map(async (item) => {
      if (!item.duplicate && item.file === item.original) item.file = await this.shrink(item.original, await createImageBitmap(item.original, { imageOrientation: "from-image" }).catch(() => null))
    })).then(() => this.sync())
  }

  // The list onto the submitted field (repeats left out), then the step lights and previews
  sync() {
    const transfer = new DataTransfer()
    for (const item of this.items) if (!item.duplicate) transfer.items.add(item.file)
    this.inputTarget.files = transfer.files
    this.show()
  }

  async shrink(file, bitmap) {
    try {
      if (!bitmap) return file
      const scale = Math.min(1, this.maxEdgeValue / Math.max(bitmap.width, bitmap.height))
      if (scale === 1 && file.type === "image/jpeg") return file
      const canvas = this.draw(bitmap, Math.round(bitmap.width * scale), Math.round(bitmap.height * scale))
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85))
      if (!blob) return file
      return new File([blob], file.name.replace(/\.[^.]+$/, "") + ".jpg", { type: "image/jpeg" })
    } catch (_) {
      return file
    }
  }

  // Like Photos::Fingerprint: shrink to 72×64 (halving first, so pixels average their area), average 8×8
  // blocks into 9×8 grey pixels (Rec. 709 luma); each bit says whether a pixel is clearly darker than
  // its right neighbour (by more than `margin` grey levels, so flat areas read 0 the same way on both
  // sides; 16 hex digits)
  fingerprint(bitmap) {
    try {
      let source = bitmap
      let [w, h] = [bitmap.width, bitmap.height]
      while (w >= 288 && h >= 256) {
        [w, h] = [Math.floor(w / 2), Math.floor(h / 2)]
        source = this.draw(source, w, h)
      }
      const px = this.draw(source, 72, 64).getContext("2d").getImageData(0, 0, 72, 64).data
      const luma = (x, y) => { const i = (y * 72 + x) * 4; return 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2] }
      const block = (bx, by) => {
        let sum = 0
        for (let y = by * 8; y < by * 8 + 8; y++) for (let x = bx * 8; x < bx * 8 + 8; x++) sum += luma(x, y)
        return sum / 64
      }
      let bits = 0n
      for (let by = 0; by < 8; by++) for (let bx = 0; bx < 8; bx++) bits = (bits << 1n) | (block(bx + 1, by) - block(bx, by) > this.marginValue ? 1n : 0n)
      return bits.toString(16).padStart(16, "0")
    } catch (_) {
      return null
    }
  }

  same(a, b) {
    let diff = BigInt("0x" + a) ^ BigInt("0x" + b)
    let count = 0
    while (diff) { count += Number(diff & 1n); diff >>= 1n }
    return count <= this.thresholdValue
  }

  draw(source, w, h) {
    const canvas = document.createElement("canvas")
    canvas.width = w
    canvas.height = h
    const context = canvas.getContext("2d")
    context.imageSmoothingQuality = "high"
    context.drawImage(source, 0, 0, w, h)
    return canvas
  }

  // Step ① done: the count, small previews (repeats tagged) with ✕, step ② lit up with how many it will upload
  show() {
    const picked = this.items
    const chosen = picked.length > 0
    const fresh = picked.filter((p) => !p.duplicate).length
    const repeats = picked.length - fresh
    this.element.toggleAttribute("data-chosen", chosen)
    this.statusTarget.hidden = chosen
    this.statusTarget.textContent = this.noneText
    this.countTarget.hidden = !chosen
    this.previewsTarget.hidden = !chosen
    this.duplicatesTarget.hidden = repeats === 0
    this.duplicatesTarget.textContent = this.plural(repeats, this.duplicateOneValue, this.duplicateOtherValue)
    this.countTarget.textContent = this.plural(picked.length, this.chosenOneValue, this.chosenOtherValue)
    this.labelTarget.textContent = fresh > 0 ? this.plural(fresh, this.uploadOneValue, this.uploadOtherValue) : this.uploadText
    if (this.hasCameraLabelTarget) this.cameraLabelTarget.textContent = chosen ? this.takeAnotherValue : this.cameraText
    this.filesLabelTarget.textContent = chosen ? this.addFilesValue : this.filesText
    this.stepOneTarget.classList.toggle("bg-green-700", chosen)
    this.stepOneTarget.classList.toggle("bg-blue-700", !chosen)
    this.stepTwoTarget.classList.toggle("bg-blue-700", fresh > 0)
    this.stepTwoTarget.classList.toggle("text-white", fresh > 0)
    this.stepTwoTarget.classList.toggle("bg-gray-300", fresh === 0)
    this.submitTarget.disabled = fresh === 0
    this.clearPreviews()
    picked.forEach(({ original, duplicate }, index) => {
      const tile = document.createElement("span")
      tile.className = "relative block h-16 w-16"
      const img = document.createElement("img")
      img.src = URL.createObjectURL(original)
      img.alt = original.name
      img.className = duplicate ? "h-16 w-16 rounded border-2 border-dashed border-amber-500 object-cover opacity-60" : "h-16 w-16 rounded border object-cover"
      tile.append(img)
      if (duplicate) {
        const tag = document.createElement("span")
        tag.className = "absolute inset-x-0.5 bottom-0.5 truncate rounded bg-amber-800 py-px text-center text-[9px] font-bold text-white"
        tag.textContent = this.tagValue
        tile.append(tag)
      }
      const remove = document.createElement("button")
      remove.type = "button"
      remove.dataset.index = index
      remove.dataset.action = "photo-upload#drop"
      remove.setAttribute("aria-label", this.removeValue.replace("%{name}", original.name))
      remove.className = "absolute -right-1.5 -top-1.5 flex h-6 w-6 cursor-pointer items-center justify-center rounded-full border-2 border-gray-900 bg-white text-xs font-bold text-gray-900"
      remove.textContent = "✕"
      tile.append(remove)
      this.previewsTarget.append(tile)
    })
  }

  plural(n, one, other) { return n === 1 ? one : other.replace("%{count}", n) }

  clearPreviews() {
    if (!this.hasPreviewsTarget) return
    this.previewsTarget.querySelectorAll("img").forEach((img) => URL.revokeObjectURL(img.src))
    this.previewsTarget.replaceChildren()
  }

  // While preparing: Upload waits and the status line says so
  busy(on) {
    this.submitTarget.disabled = on
    this.statusTarget.hidden = !on
    this.statusTarget.textContent = on ? this.workingValue : this.noneText
  }
}
