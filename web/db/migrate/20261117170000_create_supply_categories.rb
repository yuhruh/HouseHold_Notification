# Supply categories become each ledger's own (they were six fixed kinds). Every ledger starts with the
# six, its items move to the matching one, and supplies.kind goes.
class CreateSupplyCategories < ActiveRecord::Migration[8.1]
  # key, 中文, English, expiry alerts a week ahead
  DEFAULTS = [
    [ "toiletries", "盥洗用品", "Toiletries", false ], [ "cleaning", "清潔用品", "Cleaning", false ], [ "kitchen", "廚房用品", "Kitchen", false ],
    [ "food_drink", "食品飲料", "Food & drink", true ], [ "health", "保健醫療", "Health", true ], [ "other", "其他", "Other", false ]
  ].freeze

  def up
    create_table :supply_categories do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name_zh, null: false
      t.string :name_en
      t.string :key
      t.boolean :perishable, null: false, default: false
      t.integer :position, null: false, default: 0
      t.datetime :archived_at
      t.timestamps
      t.index %i[household_id name_zh], unique: true
      t.index %i[household_id key], unique: true, where: "key IS NOT NULL"
    end
    add_reference :supplies, :supply_category, foreign_key: true

    DEFAULTS.each_with_index do |(key, name_zh, name_en, perishable), position|
      execute(<<~SQL.squish)
        INSERT INTO supply_categories (household_id, key, name_zh, name_en, perishable, position, created_at, updated_at)
        SELECT id, #{quote(key)}, #{quote(name_zh)}, #{quote(name_en)}, #{perishable}, #{position}, NOW(), NOW() FROM households
      SQL
    end
    execute(<<~SQL.squish)
      UPDATE supplies SET supply_category_id = supply_categories.id FROM supply_categories
      WHERE supply_categories.household_id = supplies.household_id AND supply_categories.key = supplies.kind
    SQL
    execute(<<~SQL.squish)
      UPDATE supplies SET supply_category_id = supply_categories.id FROM supply_categories
      WHERE supplies.supply_category_id IS NULL AND supply_categories.household_id = supplies.household_id AND supply_categories.key = 'other'
    SQL
    change_column_null :supplies, :supply_category_id, false
    remove_column :supplies, :kind
  end

  def down
    add_column :supplies, :kind, :string, null: false, default: "other"
    execute(<<~SQL.squish)
      UPDATE supplies SET kind = supply_categories.key FROM supply_categories
      WHERE supply_categories.id = supplies.supply_category_id AND supply_categories.key IS NOT NULL
    SQL
    remove_reference :supplies, :supply_category, foreign_key: true
    drop_table :supply_categories
  end
end
