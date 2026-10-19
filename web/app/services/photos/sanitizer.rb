module Photos
  # Runs on the uploaded tempfile before anything is attached (PRD §7): auto-rotate from EXIF,
  # strip every piece of metadata (EXIF, GPS, XMP, ICC → sRGB), downscale to ≤2000px and re-encode
  # as JPEG. HEIC becomes JPEG too. The original never reaches the volume.
  module Sanitizer
    class Invalid < StandardError; end

    LONG_EDGE = 2000
    QUALITY = 82
    AVATAR = 512

    module_function

    def call(path, avatar: false)
      require "image_processing/vips"
      pipeline = ImageProcessing::Vips.source(path).autorot.colourspace(:srgb)
      pipeline = avatar ? pipeline.resize_to_fill(AVATAR, AVATAR) : pipeline.resize_to_limit(LONG_EDGE, LONG_EDGE)
      pipeline.convert("jpg").saver(strip: true, Q: QUALITY).call
    rescue Vips::Error, ImageProcessing::Error => e
      raise Invalid, e.message
    end
  end
end
