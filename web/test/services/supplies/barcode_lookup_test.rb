require "test_helper"

class Supplies::BarcodeLookupTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    @urls = []
  end

  def lookup(code, responses = {}, yahoo: nil)
    urls = @urls
    fetcher = ->(url) { urls << url; responses.find { |host, _| url.include?(host) }&.last }
    Supplies::BarcodeLookup.call(@home, code, fetcher:, yahoo_client_id: yahoo)
  end

  test "a barcode saved on one of the household's items skips the network" do
    supply = @home.supplies.create!(name: "Toilet paper", kind: "toiletries", unit: "roll", level: 0)
    supply.barcodes.create!(household: @home, code: "4710000000017")
    result = lookup("4710000000017")
    assert_equal supply, result.supply
    assert_empty @urls
  end

  test "Open Food Facts fills the name and kind, and the answer is cached for every household" do
    body = { status: 1, product: { product_name: "Oat milk", product_name_zh: "燕麥奶", brands: "Oatly, Other" } }.to_json
    result = lookup("7394376616228", { "openfoodfacts" => body })
    assert_equal [ "燕麥奶", "Oat milk", "Oatly", "food_drink", "open_food_facts" ], [ result.name, result.original_name, result.brand, result.kind, result.source ]
    @urls.clear
    assert_equal "燕麥奶", Supplies::BarcodeLookup.call(households(:parents), "7394376616228", fetcher: ->(_) { flunk "asked again" }, yahoo_client_id: nil).name
  end

  test "a Japanese code falls through the open databases to Yahoo! JAPAN, only with a Client ID" do
    yahoo = { hits: [ { name: "キュキュット 食器用洗剤", brand: { name: "花王" } } ] }.to_json
    assert_not lookup("4901301000003", { "yahooapis" => yahoo }).found?, "no Client ID: skipped"
    ProductLookup.delete_all
    result = lookup("4901301000003", { "yahooapis" => yahoo }, yahoo: "client")
    assert_equal [ "キュキュット 食器用洗剤", "花王", "yahoo_japan" ], [ result.name, result.brand, result.source ]
    assert @urls.last.include?("jan_code=4901301000003")
    assert @urls.none? { it.include?("example.com") }
  end

  test "a timeout or garbage counts as not found" do
    result = lookup("4710000000017", { "openfoodfacts" => "<html>" })
    assert_not result.found?
    assert_not result.known?
    assert_not Supplies::BarcodeLookup.valid?("12345")
  end
end
