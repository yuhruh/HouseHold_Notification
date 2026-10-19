class SeedCategoriesForExistingHouseholds < ActiveRecord::Migration[8.1]
  def up
    Category.reset_column_information
    Household.find_each { |household| Categories::Seed.call(household) }
  end

  def down; end
end
