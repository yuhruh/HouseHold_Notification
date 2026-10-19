require "test_helper"

class Photos::SanitizerTest < ActiveSupport::TestCase
  def fields(path) = Vips::Image.new_from_file(path).get_fields

  test "auto-rotates from EXIF and strips every piece of metadata" do
    source = jpeg_fixture(width: 300, height: 200, orientation: 6)
    assert_includes fields(source), "xmp-data"
    clean = Photos::Sanitizer.call(source)
    image = Vips::Image.new_from_file(clean.path)
    assert_equal [ 200, 300 ], [ image.width, image.height ], "orientation 6 rotated into place"
    assert_empty image.get_fields.grep(/\A(exif|xmp|iptc|icc)|orientation/), "no EXIF, GPS, XMP or ICC left"
    assert_equal "image/jpeg", Marcel::MimeType.for(Pathname(clean.path))
  end

  test "downscales to 2000px on the long edge; avatars are 512 square" do
    source = jpeg_fixture(width: 3000, height: 1500, with_metadata: false)
    image = Vips::Image.new_from_file(Photos::Sanitizer.call(source).path)
    assert_equal [ 2000, 1000 ], [ image.width, image.height ]
    avatar = Vips::Image.new_from_file(Photos::Sanitizer.call(source, avatar: true).path)
    assert_equal [ 512, 512 ], [ avatar.width, avatar.height ]
  end

  test "HEIC becomes JPEG; garbage is rejected" do
    begin
      Vips::Image.new_from_file(file_fixture("sample.heic").to_s).avg
    rescue Vips::Error
      skip "this machine's libheif has no HEVC decoder (the production image has it, M0 check X5)"
    end
    clean = Photos::Sanitizer.call(file_fixture("sample.heic").to_s)
    assert_equal "image/jpeg", Marcel::MimeType.for(Pathname(clean.path))
    junk = Rails.root.join("tmp", "junk.jpg").tap { |p| File.write(p, "not an image") }
    assert_raises(Photos::Sanitizer::Invalid) { Photos::Sanitizer.call(junk.to_s) }
  end
end
