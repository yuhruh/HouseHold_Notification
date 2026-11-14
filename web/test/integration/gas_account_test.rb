require "test_helper"

class GasAccountTest < ActionDispatch::IntegrationTest
  Gas = Utilities::ShintaoGas

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @gas = @home.categories.find_by!(name_zh: "瓦斯費")
    @open_bill = @home.records.create!(record_type: "expense", category: @gas, details: "瓦斯費", period: Period.parse(2026, "7月-8月"))
  end

  teardown { Gas::Client.singleton_class.send(:remove_method, :new) if Gas::Client.singleton_class.method_defined?(:new, false) }

  # 欣桃 answers from the fixtures (paid: a real household's last 12 bills; nothing unpaid), or fails
  def gas_answers(error: nil)
    fixture = ->(name) { JSON.parse(File.read(Rails.root.join("test/fixtures/files/shintao_gas/#{name}.json")))["Data"]["Details"].map { Gas::Client.bill(it) } }
    fake = Object.new
    fake.define_singleton_method(:paid) { error ? raise(error) : fixture.("paid") }
    fake.define_singleton_method(:unpaid) { fixture.("unpaid_none") }
    Gas::Client.define_singleton_method(:new) { |*| fake }
  end

  test "the owner connects the 用戶編號; it's checked at once and the open gas bill is marked paid" do
    sign_in_as users(:alex)
    get household_gas_account_path(@home)
    assert_response :success
    assert_select "select[name='gas_account[category_id]'] option[selected]", "瓦斯費"
    assert_select "nav[aria-label=?] a[aria-current=page][href=?]", "帳本設定項目", household_gas_account_path(@home)

    gas_answers
    patch household_gas_account_path(@home), params: { gas_account: { customer_code: "1234 567 890", category_id: @gas.id, enabled: "1" } }
    assert_redirected_to household_gas_account_path(@home)
    account = @home.reload.gas_account
    assert_equal "1234567890", account.customer_code
    assert @open_bill.reload.settled
    follow_redirect!
    assert_select "h2#gas-status", /已連結/
    assert_select "li", /標示已付款：2026 7月-8月，NT\$374/

    post check_household_gas_account_path(@home)
    follow_redirect!
    assert_select "p", /已向欣桃天然氣查詢，沒有新的變動/

    get household_pending_path(@home)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@open_bill)}", 0, "paid, so not on To Pay"

    get household_record_path(@home, @open_bill)
    assert_select "p", "由欣桃天然氣同步"
    assert_select "li", /由欣桃天然氣標示已付款.*欣桃天然氣自動同步/m
  end

  test "a failed check says so and changes nothing" do
    sign_in_as users(:alex)
    @home.create_gas_account!(customer_code: "1234567890", category: @gas)
    gas_answers(error: Gas::Error.new("HTTP 503"))
    post check_household_gas_account_path(@home)
    follow_redirect!
    assert_select "p", /無法向欣桃天然氣查詢（HTTP 503）/
    assert_not @open_bill.reload.settled
  end

  test "a wrong number is refused, and a number another ledger uses can't be taken" do
    sign_in_as users(:alex)
    patch household_gas_account_path(@home), params: { gas_account: { customer_code: "123", category_id: @gas.id } }
    assert_response :unprocessable_content
    parents = households(:parents)
    Categories::Seed.call(parents)
    parents.create_gas_account!(customer_code: "1234567890", category: parents.categories.find_by!(name_zh: "瓦斯費"))
    patch household_gas_account_path(@home), params: { gas_account: { customer_code: "1234567890", category_id: @gas.id } }
    assert_response :unprocessable_content
    assert_select "li", /已連結到另一本帳本/
  end

  test "disconnecting keeps the bills" do
    sign_in_as users(:alex)
    @home.create_gas_account!(customer_code: "1234567890", category: @gas)
    delete household_gas_account_path(@home)
    assert_nil @home.reload.gas_account
    assert Record.exists?(@open_bill.id)
  end

  test "only the owner sees and uses it; the settings menu leaves out owner-only sections for others" do
    sign_in_as users(:google_only) # a viewer
    get household_gas_account_path(@home)
    assert_response :forbidden
    post check_household_gas_account_path(@home)
    assert_response :forbidden
    get danger_household_settings_path(@home)
    assert_response :forbidden
    get household_settings_path(@home)
    assert_select "a[href=?]", household_gas_account_path(@home), 0
    assert_select "a[href=?]", danger_household_settings_path(@home), 0
    assert_select "a[href=?]", household_members_path(@home)
    assert_select "a[href=?]", activity_household_settings_path(@home)
  end

  test "every settings section shows the menu with itself marked, and links back to the settings list" do
    sign_in_as users(:alex)
    { household_members_path(@home) => "成員", household_categories_path(@home) => "類別", household_payment_methods_path(@home) => "付款方式",
      household_recurring_templates_path(@home) => "定期帳單", household_reminder_deliveries_path(@home) => "提醒送達狀態",
      activity_household_settings_path(@home) => "活動紀錄", danger_household_settings_path(@home) => "危險區域" }.each do |path, label|
      get path
      assert_select "nav[aria-label=?] a[aria-current=page]", "帳本設定項目", { text: label }, path
      assert_select "a[href=?]", household_settings_path(@home), /‹ 帳本設定/
    end
    get household_settings_path(@home)
    assert_select "nav[aria-label=?] a[aria-current=page]", "帳本設定項目", text: "一般"
  end

  test "the daily job checks every enabled account and skips paused ones" do
    @home.create_gas_account!(customer_code: "1234567890", category: @gas)
    parents = households(:parents)
    Categories::Seed.call(parents)
    paused = parents.create_gas_account!(customer_code: "2234567890", category: parents.categories.find_by!(name_zh: "瓦斯費"), enabled: false)
    gas_answers
    SyncGasAccountsJob.perform_now
    assert @open_bill.reload.settled
    assert_nil paused.reload.last_checked_at, "a paused account isn't checked"
  end
end
