require "test_helper"

class ElectricityAccountTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @power = @home.categories.find_by!(name_zh: "電費")
    ElectricityAccount.define_singleton_method(:mailbox) { "household.bills@gmail.com" }
  end

  teardown { ElectricityAccount.singleton_class.send(:remove_method, :mailbox) }

  test "the owner turns it on without a 電號 and gets the ledger's forwarding address" do
    sign_in_as users(:alex)
    get household_electricity_account_path(@home)
    assert_response :success
    assert_select "nav[aria-label=?] a[aria-current=page][href=?]", "帳本設定項目", household_electricity_account_path(@home)
    assert_select "select[name='electricity_account[category_id]'] option[selected]", "電費"
    assert_select "button", /開啟/
    assert_select "input#electricity-address", 0, "no address before it's turned on"

    patch household_electricity_account_path(@home), params: { electricity_account: { customer_code: "", category_id: @power.id,
      allowed_senders: "Other@Example.com, other@example.com\n" } }
    assert_redirected_to household_electricity_account_path(@home)
    account = @home.reload.electricity_account
    assert_nil account.customer_code
    assert_equal [ "other@example.com" ], account.allowed_senders
    assert_match(/\A[a-z0-9]{10}\z/, account.inbox_token)
    assert_equal "household.bills+h#{@home.id}-#{account.inbox_token}@gmail.com", account.inbox_address

    follow_redirect!
    assert_select "input#electricity-address[value=?]", account.inbox_address
    assert_select "[data-controller=clipboard][data-clipboard-text-value=?]", account.inbox_address
    assert_select "h2#electricity-status", /還沒收到台電 Email/
    assert_select "dd", "從第一封台電 Email 取得"
    assert_select "ol li", 3
  end

  test "a 電號 must be 11 digits, a ledger can't take another's, and senders must be emails" do
    sign_in_as users(:alex)
    patch household_electricity_account_path(@home), params: { electricity_account: { customer_code: "0408-1234-567", category_id: @power.id } }
    assert_equal "04081234567", @home.reload.electricity_account.customer_code
    patch household_electricity_account_path(@home), params: { electricity_account: { customer_code: "123" } }
    assert_response :unprocessable_content
    patch household_electricity_account_path(@home), params: { electricity_account: { allowed_senders: "not-an-email" } }
    assert_response :unprocessable_content
    assert_select "li", /not-an-email/

    parents = households(:parents)
    Categories::Seed.call(parents)
    taken = parents.build_electricity_account(customer_code: "04081234567", category: parents.categories.find_by!(name_zh: "電費"))
    assert_not taken.valid?
    assert taken.errors.added?(:customer_code, :taken, value: "04081234567")
  end

  test "gas and electricity live side by side, one of each per ledger, each with its own rules" do
    gas = @home.categories.find_by!(name_zh: "瓦斯費")
    @home.create_gas_account!(customer_code: "1234567890", category: gas)
    @home.create_electricity_account!(category: @power)
    assert_equal %w[ElectricityAccount GasAccount], UtilityAccount.where(household: @home).pluck(:type).sort
    assert_nil @home.gas_account.inbox_token, "gas has no forwarding address"
    assert_not ElectricityAccount.new(household: @home, category: @power).valid?, "a second one for the same ledger"
    assert_not GasAccount.new(household: households(:parents), category: gas).valid?, "gas still needs its 用戶編號"
    assert_not @power.destroy, "a category in use by an account isn't deleted"
  end

  test "a co-owner sees the address but can't change it; a viewer doesn't see it at all" do
    account = @home.create_electricity_account!(category: @power)
    memberships(:sam_home).update!(role: "co_owner")
    sign_in_as users(:google_only)
    get household_electricity_account_path(@home)
    assert_response :success
    assert_select "input#electricity-address[value=?]", account.inbox_address
    assert_select "fieldset[disabled]"
    assert_select "p", /只有擁有者可以更改/
    patch household_electricity_account_path(@home), params: { electricity_account: { customer_code: "04081234567" } }
    assert_response :forbidden
    delete household_electricity_account_path(@home)
    assert_response :forbidden
    get household_settings_path(@home)
    assert_select "a[href=?]", household_electricity_account_path(@home)

    memberships(:sam_home).update!(role: "viewer")
    get household_electricity_account_path(@home)
    assert_response :forbidden
    get household_settings_path(@home)
    assert_select "a[href=?]", household_electricity_account_path(@home), 0
  end

  test "a co-owner sees that it isn't on yet" do
    memberships(:sam_home).update!(role: "co_owner")
    sign_in_as users(:google_only)
    get household_electricity_account_path(@home)
    assert_select "p", /擁有者還沒有開啟/
  end

  test "disconnecting keeps the bills" do
    sign_in_as users(:alex)
    @home.create_electricity_account!(category: @power)
    bill = @home.records.create!(record_type: "expense", category: @power, details: "電費", period: Period.parse(2026, "9月-10月"))
    delete household_electricity_account_path(@home)
    assert_nil @home.reload.electricity_account
    assert Record.exists?(bill.id)
  end

  test "without the app's mailbox the page says so instead of showing an address" do
    sign_in_as users(:alex)
    @home.create_electricity_account!(category: @power)
    ElectricityAccount.define_singleton_method(:mailbox) { nil }
    get household_electricity_account_path(@home)
    assert_select "input#electricity-address", 0
    assert_select "p", /還沒有設定 App 的信箱/
  end

  test "Gmail's confirmation code shows for the co-owner until 台電 mail starts arriving" do
    account = @home.create_electricity_account!(category: @power, forwarding_code: "123456789", forwarding_from: "co.owner@gmail.com", forwarding_code_at: 2.minutes.ago)
    memberships(:sam_home).update!(role: "co_owner")
    sign_in_as users(:google_only)
    get household_electricity_account_path(@home)
    assert_select "h3#electricity-code", "Gmail 確認碼"
    assert_select "output", "123456789"
    assert_select "p", /由 co\.owner@gmail\.com 申請/
    assert_select "[data-controller=clipboard][data-clipboard-text-value=?]", "123456789"

    account.update!(last_success_at: Time.current)
    get household_electricity_account_path(@home)
    assert_select "output", 0
    assert_select "h2#electricity-status", /轉寄正常/
  end
end
