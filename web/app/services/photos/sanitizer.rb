module Photos
  # Runs on the uploaded tempfile before anything is attached (PRD §7): auto-rotate from EXIF,
  # strip every piece of metadata (EXIF, GPS, XMP, ICC → sRGB), downscale to ≤2000px and re-encode
  # as JPEG. HEIC becomes JPEG too. The original never reaches the volume.
  #
  # The file is a stranger's, so libvips opens it with only the four decoders photos need: its many
  # others (TIFF, GIF, SVG, PDF, ImageMagick's…) are switched off for the whole process, and a file
  # one of them would have read is refused. A photo with more pixels than any phone camera takes is
  # refused before it's decoded.
  module Sanitizer
    class Invalid < StandardError; end

    LONG_EDGE = 2000
    QUALITY = 82
    AVATAR = 512
    LOADERS = { "jpegload" => "VipsForeignLoadJpeg", "pngload" => "VipsForeignLoadPng", "webpload" => "VipsForeignLoadWebp",
      "heifload" => "VipsForeignLoadHeif" }.freeze
    MAX_PIXELS = 100_000_000 # a 48-megapixel phone photo fits twice

    module_function

    def call(path, avatar: false)
      require "image_processing/vips"
      only_photo_loaders
      header = Vips::Image.new_from_file(path)
      raise Invalid, "not a photo format" unless LOADERS.key?(header.get("vips-loader")) && !av1?(header)
      raise Invalid, "too many pixels" if header.width * header.height > MAX_PIXELS

      pipeline = ImageProcessing::Vips.source(path).autorot.colourspace(:srgb)
      pipeline = avatar ? pipeline.resize_to_fill(AVATAR, AVATAR) : pipeline.resize_to_limit(LONG_EDGE, LONG_EDGE)
      pipeline.convert("jpg").saver(strip: true, Q: QUALITY).call
    rescue Vips::Error, ImageProcessing::Error => e
      raise Invalid, e.message
    end

    # Once per process (libvips 8.13+; the header check above covers an older one)
    def only_photo_loaders
      return if @only_photo_loaders

      require "vips"
      if Vips.at_least_libvips?(8, 13)
        Vips.block("VipsForeignLoad", true)
        LOADERS.each_value { Vips.block(it, false) }
      end
      @only_photo_loaders = true
    end

    # AVIF comes through the HEIF loader with another codec; it isn't one of Upload::TYPES
    def av1?(header) = header.get_typeof("heif-compression") != 0 && header.get("heif-compression").to_s == "av1"
  end
end
