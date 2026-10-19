require "test_helper"

class SpikeTest < ActionDispatch::IntegrationTest
  test "push page renders with the VAPID key and manifest is served" do
    get spike_push_path
    assert_response :success
    get pwa_manifest_path(format: :json)
    assert_equal "Household Tracker", response.parsed_body["name"]
  end

  test "subscribe stores the browser subscription" do
    post spike_push_subscription_path, params: { subscription: { endpoint: "https://fcm.googleapis.com/x", keys: { p256dh: "p", auth: "a" } } }, as: :json
    assert_response :created
    assert_equal 1, Spike::PushSubscription.count
  end

  test "receipt token marks a send received once" do
    sub = Spike::PushSubscription.create!(endpoint: "https://fcm.googleapis.com/y", p256dh: "p", auth: "a")
    push_send = sub.sends.create!(scheduled_for: Time.current, sent_at: Time.current)

    post spike_push_receipt_path(push_send.receipt_token)
    assert_response :no_content
    assert push_send.reload.received_at

    post spike_push_receipt_path(push_send.receipt_token)
    assert_response :not_found
  end

  test "volume check appends a line" do
    path = Rails.root.join("storage", Spike::ChecksController::VOLUME_FILE)
    FileUtils.rm_f(path)
    post spike_write_volume_path
    assert_redirected_to spike_checks_path
    assert_equal 1, path.read.lines.size
  ensure
    FileUtils.rm_f(path)
  end

  test "charts page renders both chart containers" do
    get spike_charts_path
    assert_response :success
    assert_select "[data-controller=spike-chart]", 2
  end
end
