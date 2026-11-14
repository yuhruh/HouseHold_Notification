require "test_helper"

class Utilities::ShintaoGasTest < ActiveSupport::TestCase
  Gas = Utilities::ShintaoGas
  TODAY = Date.new(2026, 11, 14)

  # Answers from the fixtures (a real household's answers, its number replaced by 1234567890)
  class FakeClient
    attr_reader :calls

    def initialize(paid: "paid", unpaid: "unpaid_none", error: nil)
      @paid, @unpaid, @error, @calls = paid, unpaid, error, 0
    end

    def paid = answer(@paid)
    def unpaid = answer(@unpaid)

    private

    def answer(name)
      @calls += 1
      raise @error if @error
      data = JSON.parse(File.read(Rails.root.join("test/fixtures/files/shintao_gas/#{name}.json")))["Data"]
      raise Gas::NotFound, "no customer" unless data
      data["Details"].map { Gas::Client.bill(it) }
    end
  end

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @gas = @home.categories.find_by!(name_zh: "瓦斯費")
    @account = @home.create_gas_account!(customer_code: "1234567890", category: @gas)
  end

  def bill(label, year: 2026, **attrs)
    @home.records.create!(record_type: "expense", category: @gas, details: "瓦斯費", period: Period.parse(year, label), **attrs)
  end

  def sync(client = FakeClient.new) = Gas::Sync.call(@account, today: TODAY, client:)

  test "dates and bills are read the way the site sends them, and each gets the ledger's period label" do
    assert_equal Date.new(2026, 10, 20), Gas::Client.date("/Date(1792425600000)/")
    assert_raises(Gas::Error) { Gas::Client.date("2026-10-20") }
    bills = FakeClient.new.paid
    assert_equal 12, bills.size
    first = bills.first
    assert_equal [ Date.new(2026, 10, 20), 374, Date.new(2026, 8, 5), 7 ], [ first.due_on, first.amount, first.read_from, first.usage ]
    assert_equal "2026 7月-8月", first.period.to_s, "08/05–10/04 is the 7–8月 bill"
    assert_equal "2025 11月-12月", bills.find { it.read_from == Date.new(2025, 12, 5) }.period.to_s
  end

  test "an unpaid bill entered by hand with no amount is marked paid from the paid list, its amount and due date filled in" do
    open_bill = bill("7月-8月")
    lines = sync
    open_bill.reload
    assert open_bill.settled
    assert_equal [ 374, 374, Date.new(2026, 10, 20), TODAY ], [ open_bill.amount_required, open_bill.amount_paid, open_bill.due_on, open_bill.paid_on ]
    assert_equal "欣桃天然氣自動確認繳費", open_bill.payment_note
    assert_equal "shintao:1234567890:2026-10-20", open_bill.external_ref
    assert_equal "gas_paid", RecordEvent.where(record_id: open_bill.id).sole.action
    assert_equal [ "paid" ], lines.map { it["kind"] }
  end

  test "an unpaid bill with an amount and due date is matched by them, keeping its note and payment method" do
    method = @home.payment_methods.create!(name: "玉山帳戶")
    open_bill = bill("8月", amount_required: 395, due_on: Date.new(2026, 8, 22), payment_note: "自動扣繳", payment_method: method)
    sync
    open_bill.reload
    assert open_bill.settled
    assert_equal "自動扣繳\n欣桃天然氣自動確認繳費", open_bill.payment_note
    assert_equal method, open_bill.payment_method
  end

  test "a bill already paid is left alone, and one whose amount differs is only reported, once" do
    right = bill("5月-6月", amount_required: 395, amount_paid: 395, paid_on: Date.new(2026, 9, 9))
    wrong = bill("3月-4月", amount_required: 426, amount_paid: 426, paid_on: Date.new(2026, 6, 10))
    lines = sync
    assert_equal [ [ "amount_differs", wrong.id, 491, 426 ] ], lines.map { it.values_at("kind", "record_id", "amount", "recorded") }
    assert_equal [ 395, 426 ], [ right.reload.amount_paid, wrong.reload.amount_paid ]
    assert_nil right.external_ref
    assert_empty RecordEvent.where(record_id: [ right.id, wrong.id ])

    sync
    assert_equal 1, @account.reload.activity.count { it["kind"] == "amount_differs" }, "not listed again the next day"
  end

  test "an unpaid bill whose amount differs isn't marked paid" do
    open_bill = bill("7月-8月", amount_required: 400)
    sync
    assert_not open_bill.reload.settled
    assert_equal "amount_differs", @account.reload.activity.first["kind"]
  end

  test "a new unpaid bill is added once; a bill made ahead for its period is filled in instead" do
    lines = sync(FakeClient.new(unpaid: "unpaid"))
    added = @home.records.find_by!(external_ref: "shintao:1234567890:2026-12-21")
    assert_equal [ "瓦斯費", "2026 9月-10月", 427, Date.new(2026, 12, 21), false ],
      [ added.title, added.period.to_s, added.amount_required, added.due_on, added.settled ]
    assert_nil added.created_by
    assert_equal [ "added" ], lines.map { it["kind"] }
    assert_no_difference -> { @home.records.count } do
      sync(FakeClient.new(unpaid: "unpaid"))
    end

    added.destroy!
    ahead = bill("9月-10月")
    assert_no_difference -> { @home.records.count } do
      sync(FakeClient.new(unpaid: "unpaid"))
    end
    assert_equal [ 427, Date.new(2026, 12, 21) ], ahead.reload.values_at(:amount_required, :due_on)
    assert_not ahead.settled
  end

  test "two bills that could both be one gas bill are left alone and listed to look at" do
    a = bill("7月-8月")
    b = bill("7月-8月")
    lines = sync
    assert_equal [ "needs_a_look" ], lines.map { it["kind"] }
    assert_equal [ a.id, b.id ].sort, lines.first["record_ids"].sort
    assert_not a.reload.settled
    assert_not b.reload.settled
  end

  test "only the ledger's gas category is looked at" do
    water = @home.categories.find_by!(name_zh: "水費")
    other = @home.records.create!(record_type: "expense", category: water, period: Period.parse(2026, "7月-8月"))
    sync
    assert_not other.reload.settled
  end

  test "when 欣桃 can't be reached or doesn't know the number nothing changes and the reason is kept" do
    open_bill = bill("7月-8月")
    assert_nil sync(FakeClient.new(error: Gas::Error.new("HTTP 500")))
    assert_not open_bill.reload.settled
    @account.reload
    assert_equal "HTTP 500", @account.last_error
    assert @account.last_checked_at
    assert_nil @account.last_success_at
    assert_not @account.connected?

    sync(FakeClient.new(paid: "not_found"))
    assert_equal "not_found", @account.reload.last_error

    sync
    assert @account.reload.connected?
    assert open_bill.reload.settled
  end

  test "nothing unpaid at 欣桃 adds nothing" do
    assert_no_difference -> { @home.records.count } do
      assert_equal [], sync(FakeClient.new(paid: "unpaid_none", unpaid: "unpaid_none"))
    end
  end

  test "the client posts the number and reads the answer; a non-JSON or wrong-customer answer is an error" do
    body = File.read(Rails.root.join("test/fixtures/files/shintao_gas/paid.json"))
    client = Gas::Client.new("1234567890")
    client.define_singleton_method(:post) { |path, payload| (@seen = [ path, payload ]) && body }
    assert_equal 12, client.paid.size
    assert_equal [ "/HOME/Invoice/GetPaid", '{"CUST_CODE":"1234567890"}' ], client.instance_variable_get(:@seen)

    other = Gas::Client.new("1111111111")
    other.define_singleton_method(:post) { |*| body }
    assert_raises(Gas::Error) { other.paid }
    html = Gas::Client.new("1234567890")
    html.define_singleton_method(:post) { |*| "<html>maintenance</html>" }
    assert_raises(Gas::Error) { html.paid }
  end

  test "one 用戶編號 per ledger and one ledger per 用戶編號" do
    parents = households(:parents)
    Categories::Seed.call(parents)
    taken = parents.build_gas_account(customer_code: "1234567890", category: parents.categories.find_by!(name_zh: "瓦斯費"))
    assert_not taken.valid?
    assert taken.errors.of_kind?(:customer_code, :taken)
    second = GasAccount.new(household: @home, customer_code: "1234567891", category: @gas)
    assert second.errors.empty? && !second.valid?
    assert second.errors.of_kind?(:household_id, :taken)
    assert_not GasAccount.new(household: parents, customer_code: "12345", category: parents.categories.first).valid?
    assert_not GasAccount.new(household: parents, customer_code: "2234567890", category: @gas).valid?, "another ledger's category"
  end
end
