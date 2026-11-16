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

  test "only JPEG, PNG, WebP and HEIC are opened, whatever the file is named; libvips's other decoders are off" do
    gif = Rails.root.join("tmp", "gif_named.png").tap { |p| File.binwrite(p, [ "47494638396101000100800000000000ffffff21f90401000000002c00000000010001000002024401003b" ].pack("H*")) }
    ppm = Rails.root.join("tmp", "ppm_named.jpg").tap { |p| File.write(p, "P3\n1 1\n255\n0 0 0\n") }
    [ gif, ppm ].each { |path| assert_raises(Photos::Sanitizer::Invalid, path.basename.to_s) { Photos::Sanitizer.call(path.to_s) } }
    assert_raises(Vips::Error, "off for the whole process, not only in the sanitizer") { Vips::Image.new_from_file(gif.to_s) }

    png = Rails.root.join("tmp", "real.png").to_s
    Vips::Image.black(40, 30).write_to_file(png)
    webp = Rails.root.join("tmp", "real.webp").to_s
    Vips::Image.black(40, 30).write_to_file(webp)
    [ png, webp ].each { |path| assert_equal [ 40, 30 ], Vips::Image.new_from_file(Photos::Sanitizer.call(path).path).size }
  end

  test "a photo with more pixels than a camera takes is refused before it's decoded" do
    huge = Rails.root.join("tmp", "huge.png").to_s
    Vips::Image.black(10_001, 10_000).write_to_file(huge, compression: 1)
    assert_operator File.size(huge), :<, Photos::Upload::MAX_BYTES, "small enough to upload"
    error = assert_raises(Photos::Sanitizer::Invalid) { Photos::Sanitizer.call(huge) }
    assert_equal "too many pixels", error.message
  end
end
