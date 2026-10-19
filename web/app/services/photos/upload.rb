module Photos
  # Validates and sanitizes uploads one at a time, then attaches only clean JPEGs (PRD §7)
  module Upload
    TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
    MAX_BYTES = 10.megabytes
    MAX_PHOTOS = 10

    Error = Class.new(StandardError)

    module_function

    def attach(record, files)
      files = Array(files).compact_blank
      raise Error, I18n.t("photos.errors.none") if files.empty?
      raise Error, I18n.t("photos.errors.too_many", max: MAX_PHOTOS) if record.photos.count + files.size > MAX_PHOTOS

      files.each do |file|
        raise Error, I18n.t("photos.errors.too_large", name: file.original_filename, max: MAX_BYTES / 1.megabyte) if file.size > MAX_BYTES
        type = Marcel::MimeType.for(file.tempfile, name: file.original_filename)
        raise Error, I18n.t("photos.errors.type", name: file.original_filename) unless TYPES.include?(type)

        clean = Sanitizer.call(file.tempfile.path)
        record.photos.attach(io: File.open(clean.path), filename: "#{File.basename(file.original_filename.to_s, '.*').first(80)}.jpg",
          content_type: "image/jpeg")
      rescue Sanitizer::Invalid
        raise Error, I18n.t("photos.errors.unreadable", name: file.original_filename)
      ensure
        clean&.close!
      end
    end
  end
end
