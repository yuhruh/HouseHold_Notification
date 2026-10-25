import { Controller } from "@hotwired/stimulus"

// Two-step photo form: ① Choose Photos, ② Upload (disabled until there is something to upload). After
// choosing it shows how many were picked with small previews. A photo that looks the same as one
// already on the record (Photos::Fingerprint, computed the same way here) is tagged "Already added" and
// left out of the upload; the server checks again either way. Picked or captured photos are resized
// to ≤2000px JPEG before upload (PRD §7), so 10–20 MB camera files fit the limit and upload fast on
// mobile data. If a file can't be decoded here (e.g. HEIC on some devices) the original is sent; the
// server sanitizer is the authority either way.
export default class extends Controller {
  static targets = ["input", "submit", "status", "summary", "count", "previews", "label", "stepOne", "stepTwo", "duplicates"]
  static values = { maxEdge: { type: Number, default: 2000 }, working: String, existing: Array, threshold: { type: Number, default: 5 }, margin: { type: Number, default: 6 },
                    chosenOne: String, chosenOther: String, uploadOne: String, uploadOther: String,
                    duplicateOne: String, duplicateOther: String, tag: String }

  connect() {
    this.noneText = this.statusTarget.textContent
    this.uploadText = this.labelTarget.textContent
  }

  disconnect() { this.clearPreviews() }

  async resize() {
    const files = Array.from(this.inputTarget.files)
    if (files.length === 0) return this.show([])
    this.busy(true)
    const seen = this.existingValue.slice()
    const picked = []
    const transfer = new DataTransfer()
    for (const file of files) {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" }).catch(() => null)
      const print = bitmap && this.fingerprint(bitmap)
      const duplicate = print !== null && seen.some((other) => this.same(other, print))
      if (print && !duplicate) seen.push(print)
      if (!duplicate) transfer.items.add(await this.shrink(file, bitmap))
      picked.push({ file, duplicate })
    }
    this.inputTarget.files = transfer.files
    this.busy(false)
    this.show(picked)
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

  // Step ① done: the count, small previews (repeats tagged), step ② lit up with how many it will upload
  show(picked) {
    const chosen = picked.length > 0
    const fresh = picked.filter((p) => !p.duplicate).length
    const repeats = picked.length - fresh
    this.element.toggleAttribute("data-chosen", chosen)
    this.statusTarget.hidden = chosen
    this.statusTarget.textContent = this.noneText
    this.summaryTarget.hidden = !chosen
    this.previewsTarget.hidden = !chosen
    this.duplicatesTarget.hidden = repeats === 0
    this.duplicatesTarget.textContent = this.plural(repeats, this.duplicateOneValue, this.duplicateOtherValue)
    this.countTarget.textContent = this.plural(picked.length, this.chosenOneValue, this.chosenOtherValue)
    this.labelTarget.textContent = fresh > 0 ? this.plural(fresh, this.uploadOneValue, this.uploadOtherValue) : this.uploadText
    this.stepOneTarget.classList.toggle("bg-green-700", chosen)
    this.stepOneTarget.classList.toggle("bg-blue-700", !chosen)
    this.stepTwoTarget.classList.toggle("bg-blue-700", fresh > 0)
    this.stepTwoTarget.classList.toggle("text-white", fresh > 0)
    this.stepTwoTarget.classList.toggle("bg-gray-300", fresh === 0)
    this.submitTarget.disabled = fresh === 0
    this.clearPreviews()
    for (const { file, duplicate } of picked.slice(0, 10)) {
      const tile = document.createElement("span")
      tile.className = "relative block h-16 w-16"
      const img = document.createElement("img")
      img.src = URL.createObjectURL(file)
      img.alt = file.name
      img.className = duplicate ? "h-16 w-16 rounded border-2 border-dashed border-amber-500 object-cover opacity-60" : "h-16 w-16 rounded border object-cover"
      tile.append(img)
      if (duplicate) {
        const tag = document.createElement("span")
        tag.className = "absolute inset-x-0.5 bottom-0.5 truncate rounded bg-amber-800 py-px text-center text-[9px] font-bold text-white"
        tag.textContent = this.tagValue
        tile.append(tag)
      }
      this.previewsTarget.append(tile)
    }
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
