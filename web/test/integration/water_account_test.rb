require "test_helper"

class WaterAccountTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    ForwardingInbox.define_singleton_method(:mailbox) { "household.bills@gmail.com" }
  end

  teardown { ForwardingInbox.singleton_class.send(:remove_method, :mailbox) }

  test "the owner turns Water on, and it shares Electricity's forwarding address" do
    sign_in_as users(:alex)
    electricity = @home.create_electricity_account!(category: @home.categories.find_by!(name_zh: "電費"))
    address = electricity.inbox_address

    get household_water_account_path(@home)
    assert_response :success
    assert_select "nav a[aria-current=page][href=?]", household_water_account_path(@home)
    assert_select "h1", /水費（台水）/
    assert_select "select[name='water_account[category_id]'] option[selected]", "水費"

    patch household_water_account_path(@home), params: { water_account: { customer_code: "", category_id: @water.id } }
    assert_redirected_to household_water_account_path(@home)
    assert_equal "水費設定已儲存。", flash[:notice]
    water = @home.reload.water_account
    assert_equal address, water.inbox_address, "one address per ledger"
    assert_equal 1, ForwardingInbox.where(household: @home).count

    follow_redirect!
    assert_select "input#forwarding-address[value=?]", address
    assert_select "h2#utility-status", /等待 Gmail 篩選器轉寄第一封台水 Email/
    assert_select "#forwarding-setup h3", "寄設定信給收到台水 Email 的人"
    assert_select "#forwarding-setup details li", /from:water\.gov\.tw/
  end

  test "once 台電 came through the filter, Water's step 2 shows Gmail forwarding as confirmed" do
    sign_in_as users(:alex)
    @home.create_electricity_account!(category: @home.categories.find_by!(name_zh: "電費"), last_success_at: 1.day.ago)
    @home.create_water_account!(category: @water)
    get household_water_account_path(@home)
    assert_select "span", "已確認"
    assert_select "h2#utility-status", /等待 Gmail 篩選器轉寄第一封台水 Email/, "Water's own filter hasn't forwarded yet"
  end

  test "the setup email names both companies and one filter for both when both are on" do
    @home.create_electricity_account!(category: @home.categories.find_by!(name_zh: "電費"))
    @home.create_water_account!(category: @water)
    mail = ForwardingSetupMailer.with(inbox: @home.reload.forwarding_inbox, email: "victor@gmail.com", added_by: users(:alex), locale: "zh-TW").setup
    assert_equal "#{@home.name}：把台電和台水的帳單 Email 轉寄到 Household Tracker", mail.subject
    body = mail.text_part.decoded
    assert_includes body, "from:(taipower.com.tw OR water.gov.tw)"
    assert_includes body, "已經在轉寄到這個地址了嗎"
  end

  test "the owner's setup actions on the Water page come back to it" do
    sign_in_as users(:alex)
    @home.create_water_account!(category: @water)
    assert_enqueued_emails 1 do
      post setup_email_household_forwarding_inbox_path(@home), params: { email: "alex@example.com", from: "water" }
    end
    assert_redirected_to household_water_account_path(@home, anchor: "forwarding-setup")
  end

  test "disconnecting Water keeps the address while Electricity uses it, and removes it with the last one" do
    sign_in_as users(:alex)
    electricity = @home.create_electricity_account!(category: @home.categories.find_by!(name_zh: "電費"))
    @home.create_water_account!(category: @water)
    token = @home.reload.forwarding_inbox.inbox_token

    delete household_water_account_path(@home)
    assert_nil @home.reload.water_account
    assert_equal token, @home.forwarding_inbox.inbox_token

    electricity.destroy!
    assert_nil @home.reload.forwarding_inbox
  end

  test "a co-owner sees Water but can't change it; a viewer can't open it" do
    @home.create_water_account!(category: @water)
    memberships(:sam_home).update!(role: "co_owner")
    sign_in_as users(:google_only)
    get household_water_account_path(@home)
    assert_response :success
    assert_select "fieldset[disabled]"
    patch household_water_account_path(@home), params: { water_account: { customer_code: "12345678901" } }
    assert_response :forbidden

    memberships(:sam_home).update!(role: "viewer")
    get household_water_account_path(@home)
    assert_response :forbidden
  end

  test "a 水號 must be 11 digits" do
    sign_in_as users(:alex)
    patch household_water_account_path(@home), params: { water_account: { customer_code: "22-60694826-2", category_id: @water.id } }
    assert_equal "22606948262", @home.reload.water_account.customer_code
    patch household_water_account_path(@home), params: { water_account: { customer_code: "123" } }
    assert_response :unprocessable_content
    assert_select "li", /11 位數水號/
  end

  test "a late 台水 email warns the owner, linking to the Water page" do
    travel_to Time.zone.parse("2026-10-01 10:00") do
      @home.create_water_account!(category: @water, last_bill_on: Date.new(2026, 10, 1))
    end
    travel_to Time.zone.parse("2026-12-09 10:00") do
      assert_difference(-> { Notification.count }, 1) { WarnMissingUtilityMailJob.perform_now }
    end
    note = Notification.last
    assert_equal household_water_account_path(@home), note.url
    assert_match(/台水/, note.title)
  end
end
