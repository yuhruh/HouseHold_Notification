module Photos
  # Validates and sanitizes uploads one at a time, then attaches only clean JPEGs (PRD §7). A photo
  # that looks the same as one already on the record (or earlier in the same upload) is skipped, not
  # attached twice; the result says how many were added and skipped.
  module Upload
    TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
    MAX_BYTES = 10.megabytes
    MAX_PHOTOS = 10

    Error = Class.new(StandardError)
    Result = Data.define(:added, :skipped)

    module_function

    def attach(record, files)
      files = Array(files).compact_blank
      raise Error, I18n.t("photos.errors.none") if files.empty?

      seen = Fingerprint.of(record)
      fresh = []
      skipped = 0
      files.each do |file|
        raise Error, I18n.t("photos.errors.too_large", name: file.original_filename, max: MAX_BYTES / 1.megabyte) if file.size > MAX_BYTES
        type = Marcel::MimeType.for(file.tempfile, name: file.original_filename)
        raise Error, I18n.t("photos.errors.type", name: file.original_filename) unless TYPES.include?(type)

        clean = Sanitizer.call(file.tempfile.path)
        fingerprint = Fingerprint.call(clean.path)
        if seen.any? { Fingerprint.same?(it, fingerprint) }
          skipped += 1
          clean.close!
        else
          seen << fingerprint if fingerprint
          fresh << [ file, clean, fingerprint ]
        end
      rescue Sanitizer::Invalid
        raise Error, I18n.t("photos.errors.unreadable", name: file.original_filename)
      end
      raise Error, I18n.t("photos.errors.too_many", max: MAX_PHOTOS) if record.photos.count + fresh.size > MAX_PHOTOS

      fresh.each do |file, clean, fingerprint|
        record.photos.attach(io: File.open(clean.path), filename: "#{File.basename(file.original_filename.to_s, '.*').first(80)}.jpg",
          content_type: "image/jpeg", metadata: { fingerprint: }.compact)
      end
      Result.new(added: fresh.size, skipped:)
    ensure
      fresh&.each { |_, clean, _| clean.close! }
    end
  end
end
