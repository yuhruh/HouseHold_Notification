require "vips"

# Builds test JPEGs on the fly: a size, an EXIF orientation and metadata (GPS-like XMP) to strip.
# Each one is a different random block pattern, so two fixtures never look like the same photo
module PhotoTestHelper
  def jpeg_fixture(width: 300, height: 200, orientation: nil, with_metadata: true)
    path = Rails.root.join("tmp", "photo-#{SecureRandom.hex(4)}.jpg").to_s
    blocks = Vips::Image.gaussnoise(16, 12, mean: 128, sigma: 70).resize(width / 16.0, vscale: height / 12.0, kernel: :nearest)
    image = blocks.bandjoin([ blocks, blocks ]).cast(:uchar)
    image = image.mutate do |m|
      m.set_type!(GObject::GINT_TYPE, "orientation", orientation) if orientation
      m.set_type!(GObject::GSTR_TYPE, "exif-ifd0-ImageDescription", "secret place") if with_metadata
      m.set_type!(Vips::BLOB_TYPE, "xmp-data", '<x:xmpmeta xmlns:x="adobe:ns:meta/"><exif:GPSLatitude>25,2.5N</exif:GPSLatitude></x:xmpmeta>') if with_metadata
    end
    image.jpegsave(path, keep: :all)
    path
  end

  def photo_upload(path = jpeg_fixture, type: "image/jpeg", name: "receipt.jpg")
    Rack::Test::UploadedFile.new(path, type, original_filename: name)
  end
end
