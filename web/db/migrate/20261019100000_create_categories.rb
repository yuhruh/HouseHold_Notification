class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.references :household, null: false, foreign_key: true
      t.string :record_type, null: false
      t.string :name_zh, null: false
      t.string :name_en
      t.string :detail_label_zh
      t.string :detail_label_en
      t.boolean :detail_required, null: false, default: false
      t.integer :position, null: false, default: 0
      t.datetime :archived_at

      t.timestamps
    end
    add_index :categories, %i[household_id record_type name_zh], unique: true
    add_check_constraint :categories, "record_type IN ('expense', 'maintenance', 'tax')", name: "categories_record_type"

    # Item-name → category mapping saved by imports (PRD → Import mapping)
    create_table :category_aliases do |t|
      t.references :household, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string :alias, null: false

      t.timestamps
    end
    add_index :category_aliases, %i[household_id alias], unique: true
  end
end
