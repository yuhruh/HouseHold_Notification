require "test_helper"

class PaymentMethods::FromNotesTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    @notes = [ "玉山ubear", "全支付(玉山ubear)", "UBEAR, 折50街口幣", "全支付(玉山unicard)", "街口", "中信轉帳",
               "濾網很髒, 改兩個月清洗一次" ]
    @records = @notes.map { |note| record(note) }
  end

  def record(note, payment_method: nil)
    @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "1月"), payment_note: note, payment_method:)
  end

  def plan = PaymentMethods::FromNotes.new(@home)

  test "lists the keywords found, in priority order, with what each would fill and a suggestion" do
    keywords = plan.keywords
    assert_equal %w[ubear unicard 中信轉帳 街口], keywords.map(&:keyword)
    assert_equal [ 3, 1, 1, 1 ], keywords.map(&:count), "UBEAR, 折50街口幣 matches both; ubear is listed first"
    assert_equal "new:card:玉山 ubear 卡", keywords.first.choice, "全支付(玉山ubear) counts under the ubear card"
    assert_equal [ [ "UBEAR, 折50街口幣", %w[ubear 街口] ] ], plan.overlaps
    assert_equal 1, plan.unmatched_count, "the maintenance note has no payment keyword"
  end

  test "apply fills only records without a payment method, never changes notes, and logs each change" do
    card = @home.payment_methods.create!(name: "玉山 ubear 卡", kind: "card")
    already = record("玉山ubear 中信轉帳", payment_method: @home.payment_methods.create!(name: "現金", kind: "cash"))
    assert_equal "pm:#{card.id}", plan.keywords.first.choice, "an existing method of the suggested name is reused"

    result = plan.apply!(order: %w[ubear unicard 中信轉帳 街口], choices: { "unicard" => "skip" }, user: users(:alex))
    assert_equal({ records: 5, methods: 2 }, result)
    assert_equal [ card ] * 3, @records.first(3).map { |r| r.reload.payment_method }
    assert_nil @records[3].reload.payment_method, "unicard was skipped"
    assert_equal "街口支付", @records[4].reload.payment_method.name
    assert_equal "中信轉帳", @records[5].reload.payment_method.name
    assert_nil @records[6].reload.payment_method
    assert_equal @notes, @records.map { |r| r.reload.payment_note }
    assert_equal "現金", already.reload.payment_method.name
    assert_equal 5, @home.record_events.where(action: "updated").count
  end

  test "order decides overlaps, and the saved choices come back as defaults" do
    plan.apply!(order: %w[街口 ubear unicard 中信轉帳], choices: { "中信轉帳" => "skip" }, user: users(:alex))
    assert_equal "街口支付", @records[2].reload.payment_method.name, "街口 was moved above ubear"
    assert_equal %w[街口 ubear unicard 中信轉帳], @home.payment_keywords.ordered.pluck(:keyword)
    assert_nil @home.payment_keywords.find_by!(keyword: "中信轉帳").payment_method

    record("中信轉帳")
    assert_equal [ "中信轉帳" ], plan.keywords.map(&:keyword), "only records without a payment method are listed"
    assert_equal "skip", plan.keywords.sole.choice
    assert_equal [ [ "中信轉帳" ] ] * 2, plan.matches
  end

  test "invalid choices and unknown keywords are ignored" do
    other = households(:parents).payment_methods.create!(name: "別人的卡", kind: "card")
    plan.apply!(order: %w[nope], choices: { "ubear" => "pm:#{other.id}", "街口" => "new:spaceship:X", "nope" => "new:card:Y" }, user: users(:alex))
    assert_nil @records.first.reload.payment_method, "another household's method is never used"
    assert_nil @records[4].reload.payment_method
    assert_not @home.payment_methods.exists?(name: "Y")
  end
end
