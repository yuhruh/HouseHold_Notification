module SheetImport
  # Suggests a canonical category for a sheet item name (PRD → Category mapping).
  # Item variants merge: "電費", "台電電費", "電費 (大樓)" → 電費.
  module CategorySuggester
    Suggestion = Data.define(:name, :record_type, :detail_required, :detail_label)

    RULES = [
      [ /牌照稅/, "牌照稅", :tax, "車牌號碼" ],
      [ /房屋稅/, "房屋稅", :tax, nil ],
      [ /地價稅/, "地價稅", :tax, nil ],
      [ /險/, "保險", :expense, "保單號碼或標的" ],
      [ /電費|台電/, "電費", :expense, nil ],
      [ /水費|自來水/, "水費", :expense, nil ],
      [ /瓦斯/, "瓦斯費", :expense, nil ],
      [ /管理費/, "社區管理費", :expense, nil ],
      [ /網路|電信|手機/, "網路/電信", :expense, nil ],
      [ /濾網|濾芯/, "濾網/濾芯更換", :maintenance, nil ],
      [ /冷氣/, "冷氣清洗", :maintenance, nil ]
    ].freeze

    def self.suggest(item, record_type)
      text = item.to_s.unicode_normalize(:nfkc)
      RULES.each do |pattern, name, type, label|
        next unless text.match?(pattern)
        # A keyword match from another type is still offered; the mapping tab lets the user fix it.
        return Suggestion.new(name: name, record_type: type, detail_required: label.present?, detail_label: label)
      end
      Suggestion.new(name: text.strip.presence || "其他", record_type: record_type, detail_required: false, detail_label: nil)
    end
  end
end
