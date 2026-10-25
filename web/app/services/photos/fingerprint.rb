module Photos
  # A "looks like" fingerprint of a photo (difference hash): the image shrunk to 72×64, averaged in
  # 8×8 blocks into 9×8 grey pixels (Rec. 709 luma, the same in the browser), each
  # bit saying whether a pixel is clearly darker than its right neighbour, as 16 hex digits. Re-encoding,
  # shrinking or stripping metadata barely changes it, so a photo picked again from the gallery
  # matches the copy already attached. photo_upload_controller.js computes the same in the browser.
  module Fingerprint
    # Bits that may differ for two fingerprints to count as the same photo (of 64)
    THRESHOLD = 5
    # Grey levels (of 255) a neighbour must be lighter by: flat areas (a plain background) then always
    # read 0, instead of flipping on tiny differences between the server's and the browser's shrinking
    MARGIN = 6

    module_function

    def call(path)
      require "vips"
      image = Vips::Image.thumbnail(path, 72, height: 64, size: :force).colourspace(:srgb)
      grey = image.to_a.map { |row| row.map { |r, g, b| 0.2126 * r + 0.7152 * g + 0.0722 * b } }
      rows = (0...8).map { |by| (0...9).map { |bx| grey[by * 8, 8].sum { it[bx * 8, 8].sum } / 64.0 } }
      rows.flat_map { |row| row.each_cons(2).map { |left, right| right - left > MARGIN ? 1 : 0 } }.join.to_i(2).to_s(16).rjust(16, "0")
    rescue Vips::Error
      nil
    end

    def same?(a, b) = a.present? && b.present? && (a.to_i(16) ^ b.to_i(16)).to_s(2).count("1") <= THRESHOLD

    # The record's photos' fingerprints (photos from before fingerprints have none until backfilled)
    def of(record) = record.photos.map { it.blob.metadata["fingerprint"] }.compact
  end
end
