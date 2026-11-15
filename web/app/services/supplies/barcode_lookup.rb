require "net/http"

module Supplies
  # What a product barcode (EAN-13/JAN, EAN-8, UPC) is, asked in this order:
  #   1. this household's own items (supply_barcodes): straight to that item
  #   2. the shared lookup cache (product_lookups), public product facts only
  #   3. Open Food Facts → Open Beauty Facts → Open Products Facts
  #   4. Yahoo! JAPAN Shopping for Japanese codes (45/49), when a Client ID is set
  # Only the barcode number leaves the app, with a generic User-Agent. Each request has a short
  # timeout and any failure counts as "not found", so the New item form just opens empty.
  class BarcodeLookup
    USER_AGENT = "HouseholdTracker/1.0"
    TIMEOUT = 3
    OPEN_FACTS = [
      [ "open_food_facts", "world.openfoodfacts.org", "food_drink" ],
      [ "open_beauty_facts", "world.openbeautyfacts.org", "toiletries" ],
      [ "open_products_facts", "world.openproductsfacts.org", nil ]
    ].freeze
    YAHOO_URL = "https://shopping.yahooapis.jp/ShoppingWebService/V3/itemSearch"

    Result = Data.define(:code, :supply, :source, :name, :original_name, :brand, :kind) do
      def known? = supply.present?
      def found? = name.present?
    end

    # fetcher: ->(url) { body string, or nil on any failure }; tests pass their own
    def self.call(household, code, fetcher: nil, yahoo_client_id: Rails.application.credentials.dig(:yahoo_japan, :client_id))
      new(household, code, fetcher: fetcher || method(:fetch), yahoo_client_id:).call
    end

    def self.valid?(code) = code.to_s.match?(/\A\d{8}\z|\A\d{12,14}\z/)

    def self.fetch(url)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        response = http.get(uri.request_uri, "User-Agent" => USER_AGENT, "Accept" => "application/json")
        response.is_a?(Net::HTTPSuccess) ? response.body : nil
      end
    rescue StandardError
      nil
    end

    def initialize(household, code, fetcher:, yahoo_client_id:)
      @household = household
      @code = code.to_s.gsub(/\D/, "")
      @fetcher = fetcher
      @yahoo_client_id = yahoo_client_id
    end

    def call
      return result if !self.class.valid?(@code)

      barcode = @household.supply_barcodes.includes(:supply).find_by(code: @code)
      return result(supply: barcode.supply) if barcode && barcode.supply.archived_at.nil?

      lookup = ProductLookup.find_by(code: @code)
      lookup = remember(lookup) unless lookup&.fresh?
      return result unless lookup&.found?

      result(source: lookup.source, name: lookup.name, original_name: lookup.original_name, brand: lookup.brand, kind: lookup.kind_guess)
    end

    private

    def result(**details)
      Result.new(code: @code, supply: nil, source: nil, name: nil, original_name: nil, brand: nil, kind: nil, **details)
    end

    def remember(lookup)
      found = open_facts || yahoo_japan || {}
      lookup ||= ProductLookup.new(code: @code)
      lookup.assign_attributes(source: nil, name: nil, original_name: nil, brand: nil, kind_guess: nil, raw: {}, **found, fetched_at: Time.current)
      lookup.save!
      lookup
    rescue ActiveRecord::RecordNotUnique
      ProductLookup.find_by(code: @code)
    end

    def open_facts
      OPEN_FACTS.each do |source, host, kind|
        data = json("https://#{host}/api/v2/product/#{@code}.json?fields=product_name,product_name_zh,product_name_en,product_name_ja,brands,categories_tags")
        product = data && data["status"].to_i == 1 && data["product"]
        next unless product.is_a?(Hash)

        names = product.values_at("product_name_zh", "product_name_en", "product_name", "product_name_ja").map { it.to_s.squish }.reject(&:empty?)
        next if names.empty?

        return { source:, name: names.first.truncate(60, omission: ""), original_name: (names.last if names.last != names.first),
                 brand: product["brands"].to_s.split(",").first&.squish.presence, kind_guess: kind || kind_from(product["categories_tags"]),
                 raw: product.slice("product_name", "brands", "categories_tags") }
      end
      nil
    end

    def yahoo_japan
      return nil if @yahoo_client_id.blank? || !@code.start_with?("45", "49")

      data = json("#{YAHOO_URL}?#{URI.encode_www_form(appid: @yahoo_client_id, jan_code: @code, results: 1)}")
      hit = data && Array(data["hits"]).first
      return nil unless hit.is_a?(Hash) && hit["name"].present?

      name = hit["name"].to_s.squish
      { source: "yahoo_japan", name: name.truncate(60, omission: ""), original_name: name, brand: hit.dig("brand", "name").presence, kind_guess: nil,
        raw: hit.slice("name", "brand") }
    end

    def kind_from(tags)
      tags = Array(tags).join(" ")
      return "cleaning" if tags.match?(/clean|detergent|laundry/)
      return "kitchen" if tags.match?(/kitchen|food-storage|tableware/)
      nil
    end

    def json(url)
      body = @fetcher.call(url)
      body && JSON.parse(body)
    rescue JSON::ParserError
      nil
    end
  end
end
