module Categories
  # The default categories every household starts with (PRD §3)
  class Seed
    DEFAULTS = {
      expense: [
        [ "水費", "Water" ], [ "電費", "Electricity" ], [ "瓦斯費", "Gas" ], [ "社區管理費", "Building management fee" ],
        [ "保險", "Insurance", "保單號碼或標的", "Policy no. or insured item" ], [ "網路/電信", "Internet / phone" ],
        [ "其他", "Other" ]
      ],
      maintenance: [ [ "冷氣清洗", "AC cleaning" ], [ "濾網/濾芯更換", "Filter replacement" ], [ "維修", "Repairs" ], [ "其他", "Other" ] ],
      tax: [
        [ "房屋稅", "House tax" ], [ "地價稅", "Land value tax" ],
        [ "牌照稅", "Vehicle license tax", "車牌號碼", "Plate number" ], [ "其他", "Other" ]
      ]
    }.freeze

    def self.call(household)
      DEFAULTS.each do |record_type, categories|
        categories.each_with_index do |(name_zh, name_en, label_zh, label_en), position|
          household.categories.find_or_create_by!(record_type: record_type.to_s, name_zh:) do |category|
            category.assign_attributes(name_en:, detail_label_zh: label_zh, detail_label_en: label_en,
              detail_required: label_zh.present?, position:)
          end
        end
      end
    end
  end
end
