require "test_helper"

class CategoriesTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(record_type: "expense", name_zh: "水費")
    sign_in_as users(:alex)
  end

  test "renaming keeps records, updates titles that used the old name and remembers it as an alias" do
    record = @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "1月-2月"))
    patch household_category_path(@home, @water), params: { category: { name_zh: "自來水費", name_en: "Water bill" } }
    assert_redirected_to household_categories_path(@home)
    assert_equal "自來水費", record.reload.title
    assert_equal @water, @home.category_aliases.find_by!(alias: "水費").category
  end

  test "add, delete an unused category; a used one can only be archived" do
    post household_categories_path(@home), params: { category: { record_type: "tax", name_zh: "燃料費", name_en: "Fuel fee" } }
    fuel = @home.categories.find_by!(name_zh: "燃料費")
    delete household_category_path(@home, fuel)
    assert_not Category.exists?(fuel.id)

    @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "1月"))
    delete household_category_path(@home, @water)
    assert Category.exists?(@water.id)
    post archive_household_category_path(@home, @water)
    assert @water.reload.archived_at
    get new_household_record_path(@home)
    assert_select "option", text: "水費", count: 0
  end

  test "aliases can be removed" do
    item = @home.category_aliases.create!(alias: "台水", category: @water)
    get household_categories_path(@home)
    assert_select "span", /台水/
    delete destroy_alias_household_categories_path(@home, alias_id: item.id)
    assert_not CategoryAlias.exists?(item.id)
  end

  test "viewers see categories but can't change them" do
    sign_out
    sign_in_as users(:google_only)
    get household_categories_path(@home)
    assert_response :success
    post household_categories_path(@home), params: { category: { record_type: "tax", name_zh: "x" } }
    assert_response :forbidden
  end

  test "the records list exports the filtered rows as CSV" do
    @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "1月-2月"), amount_required: 580)
    get household_records_path(@home, format: :csv)
    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=" + response.charset
    assert_includes response.body, "ID,✅,Type,year,month,Item"
    assert_includes response.body, "水費"
  end
end
