require "test_helper"

class SupplyCategoryTest < ActiveSupport::TestCase
  setup { @home = households(:home) }

  test "a new ledger starts with the six categories, two of them going off quickly; seeding again adds nothing" do
    household = Households::Create.call(user: users(:alex), params: { name: "New", default_currency: "TWD" })
    assert_equal SupplyCategory::KEYS, household.supply_categories.ordered.map(&:key)
    assert_equal %w[food_drink health], household.supply_categories.where(perishable: true).ordered.map(&:key)
    assert_equal [ "盥洗用品", "Toiletries" ], household.supply_categories.ordered.first.then { [ it.name_zh, it.name_en ] }
    assert_no_difference -> { SupplyCategory.count } do
      SupplyCategory.seed(household)
    end
  end

  test "the name follows the language, and a category with no English name shows its one name" do
    kitchen = SupplyCategory.for_key(@home, "kitchen")
    shampoo = SupplyCategory.named(@home, "洗髮精")
    assert_equal [ "廚房用品", "洗髮精" ], [ kitchen.name, shampoo.name ]
    I18n.with_locale(:en) { assert_equal [ "Kitchen", "洗髮精" ], [ kitchen.name, shampoo.name ] }
  end

  test "a starting category is found by its key after a rename; with no key, an unknown one or an archived one it's Other" do
    kitchen = SupplyCategory.for_key(@home, "kitchen")
    kitchen.update!(name_zh: "廚房", name_en: nil)
    assert_equal kitchen, SupplyCategory.for_key(@home, "kitchen")
    other = SupplyCategory.fallback(@home)
    assert other.fallback?
    assert_equal [ other, other ], [ SupplyCategory.for_key(@home, nil), SupplyCategory.for_key(@home, "garden") ]
    kitchen.update!(archived_at: Time.current)
    assert_equal other, SupplyCategory.for_key(@home, "kitchen")
  end

  test "named: an existing name in either language and any case is used, an archived one comes back, a new one goes last" do
    SupplyCategory.seed(@home)
    shampoo = SupplyCategory.named(@home, "  洗髮精  ")
    assert_equal [ "洗髮精", nil, 6, false ], [ shampoo.name_zh, shampoo.key, shampoo.position, shampoo.perishable ]
    shampoo.update!(name_en: "Shampoo", archived_at: Time.current)
    assert_no_difference -> { SupplyCategory.count } do
      assert_equal shampoo, SupplyCategory.named(@home, "SHAMPOO")
      assert_equal "kitchen", SupplyCategory.named(@home, "kitchen").key
    end
    assert_nil shampoo.reload.archived_at
    assert_not SupplyCategory.named(@home, "長" * 41).persisted?
    assert_not SupplyCategory.named(@home, " ").persisted?
    assert SupplyCategory.named(households(:parents), "洗髮精").persisted?, "another ledger can have the same name"
  end

  test "names are unique in a ledger whatever the case, and a category with items can't be deleted" do
    shampoo = SupplyCategory.named(@home, "Shampoo")
    assert_not @home.supply_categories.new(name_zh: "shampoo").valid?
    @home.supplies.create!(name: "Lux", unit: "bottle", level: 1, category: shampoo)
    assert_not shampoo.destroy
    assert SupplyCategory.exists?(shampoo.id)
  end

  test "an item: no category means Other, another ledger's is refused, and one that goes off quickly warns a week ahead" do
    item = @home.supplies.create!(name: "Lux", unit: "bottle", level: 1)
    assert item.category.fallback?
    assert_equal 30, item.expiry_window_days
    item.update!(category: SupplyCategory.named(@home, "鮮食").tap { it.update!(perishable: true) })
    assert_equal 7, item.expiry_window_days
    item.update!(kind: "health")
    assert_equal [ "health", 7 ], [ item.category.key, item.expiry_window_days ]
    item.category = SupplyCategory.for_key(households(:parents), "kitchen")
    assert_not item.valid?
    assert item.errors[:category].any?
  end
end
