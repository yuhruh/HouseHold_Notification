require "test_helper"

class Households::PurgeTest < ActiveSupport::TestCase
  test "no row with the household's id remains in any table that has a household_id column" do
    household = households(:home)
    Invitation.issue!(household:, invited_by: users(:alex), email: "x@example.com", role: "viewer", expires_at: nil)
    users(:google_only).update!(last_household: household)
    Categories::Seed.call(household)
    water = household.categories.find_by!(name_zh: "水費")
    household.category_aliases.create!(alias: "台電電費", category: water)
    card = household.payment_methods.create!(name: "Card", kind: "card")
    household.records.create!(record_type: "expense", category: water, title: "水費", payment_method: card,
      period: Period.parse(2026, "1月-2月"))

    Households::Purge.call(household, actor: users(:alex))

    conn = ActiveRecord::Base.connection
    tables = conn.tables.select { |t| conn.column_exists?(t, :household_id) } - %w[security_events]
    assert_includes tables, "memberships"
    assert_includes tables, "records"
    tables.each do |table|
      assert_equal 0, conn.select_value("SELECT COUNT(*) FROM #{conn.quote_table_name(table)} WHERE household_id = #{household.id}").to_i, table
    end
    assert_not Household.exists?(household.id)
    assert_nil users(:google_only).reload.last_household_id
    assert SecurityEvent.exists?(kind: "household_deleted", household_id: household.id)
  end
end
