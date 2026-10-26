require "test_helper"

class PhotosTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @record = @home.records.create!(record_type: "expense", category: @home.categories.find_by!(name_zh: "水費"),
      period: Period.parse(2026, "9月-10月"), amount_required: 580)
  end

  def upload(*files) = post household_record_photos_path(@home, @record), params: { photos: files }

  test "a member uploads; the clean JPEG is served privately to members only" do
    sign_in_as users(:alex)
    upload(photo_upload(jpeg_fixture(orientation: 6)))
    assert_redirected_to household_record_path(@home, @record)
    photo = @record.reload.photos.sole
    assert_equal [ "image/jpeg", "receipt.jpg" ], [ photo.content_type, photo.filename.to_s ]

    get household_record_photo_file_path(@home, @record, photo)
    assert_response :success
    assert_equal %w[max-age=300 private], response.headers["Cache-Control"].split(", ").sort
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_match "inline", response.headers["Content-Disposition"]
    get household_record_photo_file_path(@home, @record, photo, variant: "thumb")
    assert_response :success
    get household_record_path(@home, @record)
    assert_select "img[src='#{household_record_photo_file_path(@home, @record, photo, variant: 'thumb')}']"

    sign_out
    get household_record_photo_file_path(@home, @record, photo)
    assert_response :not_found, "signed out → 404, not a sign-in redirect"
    sign_in_as users(:newbie)
    get household_record_photo_file_path(@home, @record, photo)
    assert_response :not_found, "non-member → 404"
  end

  test "uploading and analysing photos doesn't touch the record, so its lock version (and an open edit form) stay valid" do
    sign_in_as users(:alex)
    lock = @record.reload.lock_version
    upload(photo_upload(jpeg_fixture), photo_upload(jpeg_fixture))
    perform_enqueued_jobs
    assert_equal 2, @record.reload.photos.count
    assert @record.photos.all? { _1.blob.analyzed? }
    assert_equal lock, @record.lock_version
  end

  test "a photo already on the record is skipped, not attached twice, and the page says so" do
    sign_in_as users(:alex)
    receipt = jpeg_fixture
    upload(photo_upload(receipt), photo_upload(jpeg_fixture))
    assert_equal "已新增 2 張照片。", flash[:notice]
    assert @record.reload.photos.all? { it.blob.metadata["fingerprint"].present? }

    upload(photo_upload(receipt), photo_upload(jpeg_fixture), photo_upload(receipt))
    assert_equal "已新增 1 張照片。 有 2 張照片已經在這筆記錄裡，已略過。", flash[:notice]
    assert_equal 3, @record.reload.photos.count

    get household_record_path(@home, @record)
    existing = JSON.parse(css_select("form[data-controller=photo-upload]").first["data-photo-upload-existing-value"])
    assert_equal Photos::Fingerprint.of(@record).sort, existing.sort
    assert_equal 3, existing.size
  end

  test "fingerprints match a re-encoded copy and tell different photos apart" do
    path = jpeg_fixture(width: 1200, height: 900)
    smaller = Rails.root.join("tmp", "photo-small-#{SecureRandom.hex(4)}.jpg").to_s
    Vips::Image.new_from_file(path).resize(0.4).jpegsave(smaller, Q: 60)
    assert Photos::Fingerprint.same?(Photos::Fingerprint.call(path), Photos::Fingerprint.call(smaller))
    assert_not Photos::Fingerprint.same?(Photos::Fingerprint.call(path), Photos::Fingerprint.call(jpeg_fixture(width: 1200, height: 900)))
  end

  test "the photo form is two numbered steps: Choose Photos, then Upload, which waits until photos are chosen" do
    sign_in_as users(:alex)
    get household_record_path(@home, @record)
    assert_select "form[data-controller=photo-upload]" do
      assert_select "input[type=file][id=record_photos_input].sr-only"
      assert_select "label[for=record_photos_input]", /選擇照片/
      assert_select "button[type=submit][disabled]", /上傳/
    end
  end

  test "no public Active Storage route exists" do
    assert_empty Rails.application.routes.routes.map { |r| r.path.spec.to_s }.grep(%r{/rails/active_storage})
    get "/rails/active_storage/blobs/redirect/abc/x.jpg"
    assert_response :not_found
  end

  test "type, size and count limits; viewers can't upload" do
    sign_in_as users(:alex)
    upload(photo_upload(file_fixture("sheet_sample.csv").to_s, type: "text/csv", name: "x.csv"))
    assert_equal I18n.t("photos.errors.type", name: "x.csv", locale: "zh-TW"), flash[:alert]
    10.times { @record.photos.attach(io: File.open(jpeg_fixture(with_metadata: false)), filename: "a.jpg", content_type: "image/jpeg") }
    upload(photo_upload)
    assert_equal I18n.t("photos.errors.too_many", max: 10, locale: "zh-TW"), flash[:alert]
    assert_equal 10, @record.photos.count

    sign_out
    sign_in_as users(:google_only)
    upload(photo_upload)
    assert_response :forbidden
  end

  test "removing a photo purges it; deleting the household purges every file" do
    sign_in_as users(:alex)
    upload(photo_upload)
    photo = @record.photos.sole
    perform_enqueued_jobs { delete household_record_photo_path(@home, @record, photo) }
    assert_not ActiveStorage::Blob.exists?(photo.blob_id)

    upload(photo_upload)
    blob = @record.photos.sole.blob
    perform_enqueued_jobs { Households::Purge.call(@home, actor: users(:alex)) }
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ActiveStorage::Attachment.exists?(blob_id: blob.id)
  end

  test "adding a photo blocks undo of the import that created the record" do
    sign_in_as users(:alex)
    batch = @home.import_batches.create!(filename: "x.csv", created_by: users(:alex))
    batch.changes_made.create!(record_id: @record.id, action: "created", after: {})
    assert_not batch.undo_blocked?
    upload(photo_upload)
    assert batch.undo_blocked?
  end

  test "avatars: sanitized square, visible to people who share a household, 404 for others" do
    sign_in_as users(:alex)
    patch avatar_path, params: { avatar: photo_upload }
    assert users(:alex).reload.avatar.attached?
    assert_equal [ 512, 512 ], Vips::Image.new_from_buffer(users(:alex).avatar.download, "").then { |i| [ i.width, i.height ] }

    sign_out
    sign_in_as users(:google_only) # shares 我的家
    get user_avatar_path(users(:alex))
    assert_response :success
    sign_out
    sign_in_as users(:newbie)
    get user_avatar_path(users(:alex))
    assert_response :not_found
  end

  test "My Account: one Choose Photo button that uploads when a photo is picked; a new photo gets a new address" do
    sign_in_as users(:alex)
    get account_path
    assert_select "form[action=?] input[type=file][onchange*=requestSubmit]", avatar_path
    assert_select "form[action=?] input[type=submit]", avatar_path, 0
    assert_select "label[for=avatar_input]", /選擇照片/

    patch avatar_path, params: { avatar: photo_upload }
    first = users(:alex).reload.avatar.blob.id
    get account_path
    assert_select "label[for=avatar_input]", /更換照片/
    assert_select "img[src=?]", user_avatar_path(users(:alex), v: first)

    patch avatar_path, params: { avatar: photo_upload }
    get account_path
    assert_select "img[src=?]", user_avatar_path(users(:alex), v: users(:alex).reload.avatar.blob.id)
    assert_not_equal first, users(:alex).avatar.blob.id
  end
end
