require "test_helper"

class Supplies::StarrersTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    @alex = users(:alex)
    @sam = users(:google_only)
  end

  test "owners and co-owners in the order they joined, each with a colour and an initial; a viewer is not one" do
    assert_equal [ [ @alex, "amber", "A", "Alex" ] ], Supplies::Starrers.new(@home).people.map { [ it.user, it.color, it.initial, it.name ] }
    assert_not Supplies::Starrers.new(@home).several?

    memberships(:sam_home).update!(role: "co_owner")
    starrers = Supplies::Starrers.new(@home)
    assert_equal [ [ @alex, "amber", "A" ], [ @sam, "teal", "S" ] ], starrers.people.map { [ it.user, it.color, it.initial ] }
    assert starrers.several?
    assert_equal "teal", starrers.find(@sam.id.to_s).color
    assert_nil starrers.find("0")
    assert_nil starrers.person(users(:newbie))
  end

  test "two people with the same first letter get two letters; no display name falls back to the email" do
    memberships(:sam_home).update!(role: "co_owner")
    @sam.update!(display_name: "amy")
    @home.memberships.create!(user: users(:newbie), role: "co_owner")
    assert_equal [ %w[Al Alex], %w[Am amy], %w[N newbie@example.com] ], Supplies::Starrers.new(@home).people.map { [ it.initial, it.name ] }
  end

  test "an item is starred while a current owner or co-owner has a star on it" do
    supply = @home.supplies.create!(name: "Coffee", kind: "food_drink", unit: "bottle", level: 3)
    supply.favorites.create!(user: @sam)
    assert_not Supplies::Starrers.new(@home).starred?(supply), "a viewer's leftover star doesn't count"

    memberships(:sam_home).update!(role: "co_owner")
    starrers = Supplies::Starrers.new(@home)
    assert starrers.starred?(supply)
    assert starrers.starred_by?(supply, @sam)
    assert_not starrers.starred_by?(supply, @alex)
    assert_equal [ @sam ], starrers.of(supply).map(&:user)
    assert_equal 1, starrers.stars.count

    supply.update!(archived_at: Time.current)
    assert_equal 0, starrers.stars.count, "only items in use"
  end
end
