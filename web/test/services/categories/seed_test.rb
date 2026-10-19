require "test_helper"

class Categories::SeedTest < ActiveSupport::TestCase
  test "a new household starts with the default categories, and only 牌照稅 and 保險 require details" do
    household = Households::Create.call(user: users(:alex), params: { name: "New", default_currency: "TWD" })
    assert_equal({ "expense" => 7, "maintenance" => 4, "tax" => 4 }, household.categories.group(:record_type).count)
    assert_equal [ [ "expense", "保險" ], [ "tax", "牌照稅" ] ], household.categories.where(detail_required: true).order(:record_type).pluck(:record_type, :name_zh)
  end

  test "seeding twice adds nothing" do
    household = households(:home)
    Categories::Seed.call(household)
    assert_no_difference(-> { Category.count }) { Categories::Seed.call(household) }
  end
end
