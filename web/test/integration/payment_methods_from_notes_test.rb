require "test_helper"

class PaymentMethodsFromNotesTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    @ubear = record("全支付(玉山ubear)")
    @jko = record("UBEAR, 折50街口幣")
  end

  def record(note)
    @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "1月"), payment_note: note)
  end

  test "owner sees one choice per keyword with the summary, and Apply fills the records" do
    sign_in_as users(:alex)
    get household_payment_methods_path(@home)
    assert_select "a[href=?]", from_notes_household_payment_methods_path(@home), "從備註指定付款方式"

    get from_notes_household_payment_methods_path(@home)
    assert_response :success
    assert_select "[data-note-keywords-target=card]", 2
    assert_select "select[name='choices[ubear]'] option[selected]", "＋ 新增：玉山 ubear 卡（信用卡）"
    assert_select "[data-note-keywords-target=summary]", /將為 2 筆記錄設定付款方式，新增 1 個付款方式/
    assert_select "p", /同時符合 「ubear」和「街口」/

    post from_notes_household_payment_methods_path(@home), params: { keywords: %w[ubear 街口], choices: { "ubear" => "new:card:玉山 ubear 卡", "街口" => "skip" } }
    assert_redirected_to household_payment_methods_path(@home)
    assert_equal "已為 2 筆記錄設定付款方式，新增 1 個付款方式。", flash[:notice]
    assert_equal [ "玉山 ubear 卡" ] * 2, [ @ubear, @jko ].map { |r| r.reload.payment_method.name }

    get from_notes_household_payment_methods_path(@home)
    assert_select "p", /沒有需要處理的付款關鍵字/
  end

  test "viewers can't open or apply it" do
    sign_in_as users(:google_only)
    get from_notes_household_payment_methods_path(@home)
    assert_response :forbidden
    post from_notes_household_payment_methods_path(@home), params: { keywords: %w[ubear], choices: { "ubear" => "new:card:X" } }
    assert_response :forbidden
    assert_nil @ubear.reload.payment_method
  end

  test "a new record's form knows the latest payment method per category" do
    card = @home.payment_methods.create!(name: "玉山 ubear 卡", kind: "card")
    @ubear.update!(payment_method: card)
    sign_in_as users(:alex)
    get new_household_record_path(@home)
    assert_select "form[data-controller=default-payment][data-default-payment-map-value=?]", { @water.id.to_s => card.id }.to_json
    get edit_household_record_path(@home, @ubear)
    assert_select "form[data-controller=default-payment]", 0
  end
end
