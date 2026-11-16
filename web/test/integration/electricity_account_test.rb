require "test_helper"

class ElectricityAccountTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @power = @home.categories.find_by!(name_zh: "電費")
    ForwardingInbox.define_singleton_method(:mailbox) { "household.bills@gmail.com" }
  end

  teardown { ForwardingInbox.singleton_class.send(:remove_method, :mailbox) }

  test "the owner turns it on without a 電號 and gets the ledger's forwarding address" do
    sign_in_as users(:alex)
    get household_electricity_account_path(@home)
    assert_response :success
    assert_select "nav[aria-label=?] a[aria-current=page][href=?]", "帳本設定項目", household_electricity_account_path(@home)
    assert_select "select[name='electricity_account[category_id]'] option[selected]", "電費"
    assert_select "button", /開啟/
    assert_select "input#forwarding-address", 0, "no address before it's turned on"

    patch household_electricity_account_path(@home), params: { electricity_account: { customer_code: "", category_id: @power.id } }
    assert_redirected_to household_electricity_account_path(@home)
    account = @home.reload.electricity_account
    assert_nil account.customer_code
    token = @home.forwarding_inbox.inbox_token
    assert_match(/\A[a-z0-9]{10}\z/, token)
    assert_equal "household.bills+h#{@home.id}-#{token}@gmail.com", account.inbox_address

    follow_redirect!
    assert_select "input#forwarding-address[value=?]", account.inbox_address
    assert_select "[data-controller=clipboard][data-clipboard-text-value=?]", account.inbox_address
    assert_select "h2#utility-status", /等待 Gmail 篩選器轉寄第一封台電 Email/
    assert_select "dd", "從第一封台電 Email 取得"
    assert_select "#forwarding-setup > ol > li", 3
    assert_select "#forwarding-setup li", /alex@example\.com · 擁有者/
    assert_select "#forwarding-setup li", /還沒寄設定信/
  end

  test "the setup checklist sits beside the bill settings; activity is folded" do
    sign_in_as users(:alex)
    @home.create_electricity_account!(category: @power, activity: [ { "at" => Time.current.iso8601, "kind" => "unreadable", "detail" => "x" } ])
    get household_electricity_account_path(@home)
    assert_select "section#forwarding-setup" do
      assert_select "h2", "設定轉寄"
      assert_select "h3", "寄設定信給收到台電 Email 的人"
      assert_select "h3", "確認 Gmail 的要求"
      assert_select "span", "目前沒有要確認的"
      assert_select "details input#forwarding-address"
    end
    assert_select "section[aria-labelledby=utility-settings] h2", "帳單設定"
    assert_select "textarea", 0, "forwarders aren't a text box any more"
    assert_select "details summary h3", "最近紀錄"
  end

  test "the owner sends the setup email, but not twice within a minute" do
    sign_in_as users(:alex)
    account = @home.create_electricity_account!(category: @power)
    assert_enqueued_emails 1 do
      post setup_email_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "Sam@example.com" }
    end
    assert_redirected_to household_electricity_account_path(@home, anchor: "forwarding-setup")
    assert_equal "已寄設定信給 sam@example.com。", flash[:notice]
    assert account.inbox.reload.setup_sent_at("sam@example.com")

    assert_no_enqueued_emails do
      post setup_email_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "sam@example.com" }
    end
    assert_match(/不到一分鐘前/, flash[:alert])

    travel 2.minutes do
      assert_enqueued_emails 1 do
        post setup_email_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "sam@example.com" }
      end
      follow_redirect!
      assert_select "button", /重寄/
    end

    assert_no_enqueued_emails do
      post setup_email_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "stranger@gmail.com" }
    end
    assert_equal "名單裡沒有這個 Email。", flash[:alert]
  end

  test "the owner adds an email that forwards, which gets the setup email, and removes it" do
    sign_in_as users(:alex)
    account = @home.create_electricity_account!(category: @power)
    assert_enqueued_emails 1 do
      post forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: " New.One@Gmail.com " }
    end
    assert_equal "已新增 new.one@gmail.com 並寄出設定信。", flash[:notice]
    inbox = account.inbox
    assert_equal [ "new.one@gmail.com" ], inbox.reload.allowed_senders
    assert inbox.setup_sent_at("new.one@gmail.com")

    assert_no_enqueued_emails do
      post forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "new.one@gmail.com" }
    end
    assert_equal "new.one@gmail.com 已經在名單裡。", flash[:alert]

    follow_redirect!
    assert_select "button[aria-label=?]", "移除 new.one@gmail.com"
    assert_select "button[aria-label=?]", "移除 alex@example.com", 0, "members can't be removed"

    delete forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "new.one@gmail.com" }
    assert_equal [], inbox.reload.allowed_senders
    assert_nil inbox.setup_sent_at("new.one@gmail.com")

    post forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "not-an-email" }
    assert_match(/not-an-email/, flash[:alert])
    assert_equal [], inbox.reload.allowed_senders
  end

  test "the owner can't use the setup email to write to address after address" do
    sign_in_as users(:alex)
    inbox = @home.create_electricity_account!(category: @power).inbox
    inbox.update!(allowed_senders: (1..ForwardingInbox::MAX_ALLOWED_SENDERS).map { "kept#{it}@example.com" })
    assert_no_enqueued_emails do
      post forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "one.more@example.com" }
    end
    assert_match(/最多 10 個/, flash[:alert])
    assert_equal ForwardingInbox::MAX_ALLOWED_SENDERS, inbox.reload.allowed_senders.size

    inbox.update!(allowed_senders: [])
    9.times do |n|
      post forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "f#{n}@example.com" }
      delete forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "f#{n}@example.com" }
    end
    assert_no_enqueued_emails do
      post forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "f9@example.com" }
    end
    assert_equal I18n.t("auth.rate_limited"), flash[:alert]
    assert_equal [], inbox.reload.allowed_senders
  end

  test "nothing to send before it's turned on" do
    sign_in_as users(:alex)
    assert_no_enqueued_emails do
      post setup_email_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "alex@example.com" }
    end
    assert_nil @home.reload.electricity_account
  end

  test "the setup email has the ledger's address, the steps and who added them" do
    account = @home.create_electricity_account!(category: @power)
    mail = ForwardingSetupMailer.with(inbox: account.inbox, email: "victor@gmail.com", added_by: users(:alex), locale: "en").setup
    assert_equal [ "victor@gmail.com" ], mail.to
    assert_equal "#{@home.name}: forward 台電's bill emails to Household Tracker", mail.subject
    body = mail.text_part.decoded
    assert_includes body, account.inbox_address
    token = account.inbox.inbox_token
    assert_includes body, "http://example.com/forward/#{token}"
    html = mail.html_part.decoded
    assert_includes html, account.inbox_address
    assert_match(%r{<a href="http://example.com/forward/#{token}"[^>]*>Copy address</a>}, html)
    assert_match(/1\. .*Forwarding and POP\/IMAP/, body)
    assert_match(/3\. .*from:taipower\.com\.tw/, body)
    assert_match(/#{Regexp.escape(users(:alex).display_name.presence || users(:alex).email_address)} confirms it/, body)
    assert_no_match(/by hand/, body + html, "an added email can't check by forwarding one by hand")

    owner_mail = ForwardingSetupMailer.with(inbox: account.inbox, email: users(:alex).email_address, added_by: users(:alex), locale: "en").setup
    assert_match(/forward one 台電 bill email to the address by hand/, owner_mail.text_part.decoded)
    assert_match(/forward one 台電 bill email to the address by hand/, owner_mail.html_part.decoded)
  end

  test "a 電號 must be 11 digits, and a ledger can't take another's" do
    sign_in_as users(:alex)
    patch household_electricity_account_path(@home), params: { electricity_account: { customer_code: "0408-1234-567", category_id: @power.id } }
    assert_equal "04081234567", @home.reload.electricity_account.customer_code
    patch household_electricity_account_path(@home), params: { electricity_account: { customer_code: "123" } }
    assert_response :unprocessable_content

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
    assert_not @home.gas_account.respond_to?(:inbox_address), "gas has no forwarding address"
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
    assert_select "input#forwarding-address[value=?]", account.inbox_address
    assert_select "fieldset[disabled]"
    assert_select "p", /只有擁有者可以更改/
    assert_select "p", /只有擁有者可以寄送設定信/
    assert_select "#forwarding-setup form", 0
    assert_select "#forwarding-setup li", /alex@example\.com/
    patch household_electricity_account_path(@home), params: { electricity_account: { customer_code: "04081234567" } }
    assert_response :forbidden
    delete household_electricity_account_path(@home)
    assert_response :forbidden
    post setup_email_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "alex@example.com" }
    assert_response :forbidden
    post forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "x@gmail.com" }
    assert_response :forbidden
    delete forwarder_household_forwarding_inbox_path(@home), params: { from: "electricity", email: "x@gmail.com" }
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
    ForwardingInbox.define_singleton_method(:mailbox) { nil }
    get household_electricity_account_path(@home)
    assert_select "input#forwarding-address", 0
    assert_select "p", /還沒有設定 App 的信箱/
  end

  test "Gmail's confirmation shows as a Confirm button for the co-owner until 台電 mail starts arriving" do
    link = "https://mail-settings.google.com/mail/vf-%5BANG%5D-abc"
    account = @home.create_electricity_account!(category: @power)
    account.inbox.update!(forwarding_link: link, forwarding_from: "co.owner@gmail.com", forwarding_code_at: 2.minutes.ago)
    memberships(:sam_home).update!(role: "co_owner")
    sign_in_as users(:google_only)
    get household_electricity_account_path(@home)
    assert_select "h4#forwarding-confirm", "確認轉寄"
    assert_select "a[href=?][target=_blank][rel~=noopener]", link, /確認轉寄/
    assert_select "p", /co\.owner@gmail\.com 要求 Gmail 轉寄到這本帳本/

    account.update!(last_success_at: Time.current)
    get household_electricity_account_path(@home)
    assert_select "a[href=?]", link, 0
    assert_select "h2#utility-status", /轉寄正常/
  end

  test "the page says when the next 台電 email is expected, and when it's late" do
    sign_in_as users(:alex)
    travel_to Time.zone.parse("2026-10-08 10:00") do
      @home.create_electricity_account!(category: @power, last_success_at: Time.current)
    end
    travel_to Time.zone.parse("2026-11-15 10:00") do
      get household_electricity_account_path(@home)
      assert_select "dd", /2026-12-08 左右/
      assert_select "dd", { text: /已逾期/, count: 0 }
      assert_select "span", /運作中 · 最近/
    end
    travel_to Time.zone.parse("2026-12-16 10:00") do
      get household_electricity_account_path(@home)
      assert_select "dd.text-amber-800", /已逾期，已通知擁有者/
      assert_select "span", /逾期 · 原本預計約/
    end
  end

  test "the setup email's copy page shows only the address, without signing in" do
    account = @home.create_electricity_account!(category: @power)
    get forwarding_address_path(token: account.inbox.inbox_token)
    assert_response :success
    assert_select "h1", /#{@home.name}/
    assert_select "[data-clipboard-text-value=?]", account.inbox_address
    assert_select "a[href^='/households']", 0

    get forwarding_address_path(token: "zzzzzzzzzz")
    assert_response :not_found
    assert_select "p", /轉寄地址已經失效|no longer works/
  end
end
