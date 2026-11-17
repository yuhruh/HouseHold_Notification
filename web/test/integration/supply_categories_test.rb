require "test_helper"

class SupplyCategoriesTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    SupplyCategory.seed(@home)
    sign_in_as users(:alex)
  end

  def category(key) = @home.supply_categories.find_by!(key:)

  SELECT = "select[name='supply[supply_category_id]']".freeze

  test "the item form lists the ledger's categories and ends with New category; naming one saves it with the item" do
    get new_household_supply_path(@home)
    assert_select "label[for=supply_supply_category_id]", "類別"
    assert_select "#{SELECT} option", 7
    assert_select "#{SELECT} option[selected]", "其他"
    assert_select "#{SELECT} option:last-child[value=new]", "＋ 新增類別…"
    assert_select "div[data-controller=new-category] div[data-new-category-target=field][hidden] input[name=new_category_name]:not([required])"

    assert_difference -> { @home.supply_categories.count } => 1, -> { @home.supplies.count } => 1 do
      post household_supplies_path(@home), params: { new_category_name: "  洗髮精 ", supply: { name: "Lux", supply_category_id: "new", unit: "bottle", level: 2 } }
    end
    shampoo = @home.supply_categories.find_by!(name_zh: "洗髮精")
    assert_equal [ nil, false, 6 ], [ shampoo.key, shampoo.perishable, shampoo.position ]
    assert_equal shampoo, @home.supplies.find_by!(name: "Lux").category
    follow_redirect!
    assert_select "p", /瓶 · 洗髮精/

    # the next item can pick it; typing its name again (any case, either language) uses it, not a second one
    get new_household_supply_path(@home)
    assert_select "#{SELECT} option[value='#{shampoo.id}']", "洗髮精"
    shampoo.update!(name_en: "Shampoo")
    assert_no_difference -> { @home.supply_categories.count } do
      post household_supplies_path(@home), params: { new_category_name: "shampoo", supply: { name: "Pantene", supply_category_id: "new", unit: "bottle", level: 1 } }
    end
    assert_equal shampoo, @home.supplies.find_by!(name: "Pantene").category
  end

  test "New category with no name or one too long saves nothing and keeps what was typed; an item that isn't saved leaves no category" do
    nothing = [ -> { @home.supply_categories.count }, -> { @home.supplies.count } ]
    assert_no_difference nothing do
      post household_supplies_path(@home), params: { new_category_name: " ", supply: { name: "Lux", supply_category_id: "new", unit: "bottle", level: 2 } }
    end
    assert_response :unprocessable_content
    assert_select "li", "請輸入新類別的名稱。"
    assert_select "#{SELECT} option[selected][value=new]"
    assert_select "div[data-new-category-target=field]:not([hidden]) input[name=new_category_name][required]"

    assert_no_difference nothing do
      post household_supplies_path(@home), params: { new_category_name: "長" * 41, supply: { name: "Lux", supply_category_id: "new", unit: "bottle", level: 2 } }
    end
    assert_response :unprocessable_content
    assert_select "input[name=new_category_name][value=?]", "長" * 41

    assert_no_difference nothing do
      post household_supplies_path(@home), params: { new_category_name: "洗髮精", supply: { name: "", supply_category_id: "new", unit: "bottle", level: 2 } }
    end
    assert_response :unprocessable_content
    assert_select "input[name=new_category_name][value=洗髮精]"
  end

  test "edit moves an item to another category or a new one; an archived category stays only on the items in it" do
    item = @home.supplies.create!(name: "Lux", kind: "toiletries", unit: "bottle", level: 1)
    get edit_household_supply_path(@home, item)
    assert_select "#{SELECT} option[selected]", "盥洗用品"
    patch household_supply_path(@home, item), params: { supply: { name: "Lux", supply_category_id: category("cleaning").id, unit: "bottle" } }
    assert_equal "cleaning", item.reload.category.key
    patch household_supply_path(@home, item), params: { new_category_name: "洗髮精", supply: { name: "Lux", supply_category_id: "new", unit: "bottle" } }
    shampoo = @home.supply_categories.find_by!(name_zh: "洗髮精")
    assert_equal shampoo, item.reload.category
    patch household_supply_path(@home, item), params: { new_category_name: "", supply: { name: "Lux 2", supply_category_id: "new", unit: "bottle" } }
    assert_response :unprocessable_content
    assert_equal "Lux", item.reload.name

    shampoo.update!(archived_at: Time.current)
    get new_household_supply_path(@home)
    assert_select "#{SELECT} option", text: "洗髮精", count: 0
    get edit_household_supply_path(@home, item)
    assert_select "#{SELECT} option[selected]", "洗髮精"
    get household_supply_path(@home, item)
    assert_select "p", /洗髮精/
    # naming an archived category on the form brings it back
    post household_supplies_path(@home), params: { new_category_name: "洗髮精", supply: { name: "Pantene", supply_category_id: "new", unit: "bottle", level: 1 } }
    assert_nil shampoo.reload.archived_at
  end

  test "another ledger's category is refused on an item" do
    theirs = SupplyCategory.for_key(households(:parents), "kitchen")
    assert_no_difference -> { Supply.count } do
      post household_supplies_path(@home), params: { supply: { name: "X", supply_category_id: theirs.id, unit: "piece", level: 1 } }
    end
    assert_response :unprocessable_content
  end

  test "a scanned product starts in the starting category the lookup guessed, renamed or not, or in Other once that was archived" do
    ProductLookup.create!(code: "7394376616228", source: "open_food_facts", name: "燕麥奶", kind_guess: "food_drink", fetched_at: Time.current)
    scan = -> { get scan_barcode_household_supplies_path(@home, code: "7394376616228"); follow_redirect! }
    scan.call
    assert_select "#{SELECT}.bg-green-50 option[selected]", "食品飲料"
    category("food_drink").update!(name_zh: "吃的喝的")
    scan.call
    assert_select "#{SELECT} option[selected]", "吃的喝的"
    category("food_drink").update!(archived_at: Time.current)
    scan.call
    assert_select "#{SELECT} option[selected]", "其他"
  end

  test "Settings › Categories lists the supply categories: add, rename, archive one with items, delete an empty one; Other always stays" do
    @home.supplies.create!(name: "Paper", kind: "toiletries", unit: "roll", level: 1)
    toiletries, kitchen, other = %w[toiletries kitchen other].map { category(it) }
    get household_categories_path(@home)
    assert_select "section#supplies h2", /日用品/
    assert_select "section#supplies > ul > li", 6
    assert_select "section#supplies li", text: /盥洗用品 \/ Toiletries\s+1 個品項/
    assert_select "section#supplies li", text: /食品飲料 \/ Food & drink\s+沒有品項 · 到期前一週提醒/
    assert_select "section#supplies li", text: /其他 \/ Other\s+沒有品項 · 固定保留/
    assert_select "section#supplies a[href=?]", new_household_supply_category_path(@home)
    assert_select "section#supplies form[action=?]", archive_household_supply_category_path(@home, toiletries)
    assert_select "section#supplies form[action=?] input[name=_method][value=delete]", household_supply_category_path(@home, kitchen)
    assert_select "section#supplies a[href=?]", edit_household_supply_category_path(@home, other)
    assert_select "section#supplies form[action*='/#{other.id}']", 0

    get new_household_supply_category_path(@home)
    assert_select "input[name='supply_category[name_zh]'][required]"
    assert_select "input[type=checkbox][name='supply_category[perishable]']"
    post household_supply_categories_path(@home), params: { supply_category: { name_zh: "洗面乳", name_en: "Face wash", perishable: "1" } }
    assert_redirected_to household_categories_path(@home, anchor: "supplies")
    face = @home.supply_categories.find_by!(name_zh: "洗面乳")
    assert_equal [ "Face wash", true, 6, nil ], [ face.name_en, face.perishable, face.position, face.key ]
    post household_supply_categories_path(@home), params: { supply_category: { name_zh: "洗面乳" } }
    assert_response :unprocessable_content

    get edit_household_supply_category_path(@home, toiletries)
    assert_select "input[name='supply_category[name_zh]'][value=盥洗用品]"
    patch household_supply_category_path(@home, toiletries), params: { supply_category: { name_zh: "浴室用品", name_en: "Bathroom", perishable: "0" } }
    assert_equal [ "浴室用品", "Bathroom", "toiletries" ], toiletries.reload.then { [ it.name_zh, it.name_en, it.key ] }
    patch household_supply_category_path(@home, toiletries), params: { supply_category: { name_zh: "" } }
    assert_response :unprocessable_content

    delete household_supply_category_path(@home, toiletries)
    assert_match "封存", flash[:alert]
    assert SupplyCategory.exists?(toiletries.id), "it has an item"
    post archive_household_supply_category_path(@home, toiletries)
    assert toiletries.reload.archived_at
    get household_categories_path(@home)
    assert_select "section#supplies li.text-gray-400", text: /浴室用品.*已封存/m
    get household_supplies_path(@home, tab: "all")
    assert_select "main li", text: /Paper.*浴室用品/m, count: 1
    post archive_household_supply_category_path(@home, toiletries)
    assert_nil toiletries.reload.archived_at
    delete household_supply_category_path(@home, kitchen)
    assert_not SupplyCategory.exists?(kitchen.id)

    patch household_supply_category_path(@home, other), params: { supply_category: { name_zh: "雜項", name_en: "Misc" } }
    assert_equal "雜項", other.reload.name_zh
    post archive_household_supply_category_path(@home, other)
    assert_response :forbidden
    delete household_supply_category_path(@home, other)
    assert_response :forbidden
    assert_nil other.reload.archived_at
  end

  test "a viewer sees the supply categories but can't change them, and another ledger's aren't found" do
    kitchen = category("kitchen")
    sign_in_as users(:google_only)
    get household_categories_path(@home)
    assert_select "section#supplies > ul > li", 6
    assert_select "section#supplies a", 0
    assert_select "section#supplies form", 0
    get new_household_supply_category_path(@home)
    assert_response :forbidden
    post household_supply_categories_path(@home), params: { supply_category: { name_zh: "洗面乳" } }
    assert_response :forbidden
    patch household_supply_category_path(@home, kitchen), params: { supply_category: { name_zh: "X" } }
    assert_response :forbidden
    post archive_household_supply_category_path(@home, kitchen)
    assert_response :forbidden
    delete household_supply_category_path(@home, kitchen)
    assert_response :forbidden
    assert_equal [ "廚房用品", nil ], kitchen.reload.then { [ it.name_zh, it.archived_at ] }

    sign_in_as users(:alex)
    theirs = SupplyCategory.for_key(households(:parents), "kitchen")
    patch household_supply_category_path(@home, theirs), params: { supply_category: { name_zh: "X" } }
    assert_response :not_found
  end
end
