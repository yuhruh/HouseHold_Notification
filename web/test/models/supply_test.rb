require "test_helper"

class SupplyTest < ActiveSupport::TestCase
  setup { @home = households(:home) }

  def item(**attrs) = @home.supplies.new(name: "Pet snack", unit: "pack", level: 0, **attrs)

  test "a pack, box or bag keeps its size; what's inside is pieces unless said" do
    %w[pack box bag].each do |unit|
      supply = item(unit:, pack_size: 4)
      assert supply.valid?, supply.errors.full_messages.to_sentence
      assert_equal [ 4, "piece" ], [ supply.pack_size, supply.pack_unit ]
      assert supply.packed?
    end
    paper = item(pack_size: 12, pack_unit: "roll")
    assert paper.valid?
    assert_equal "roll", paper.pack_unit
  end

  test "any other unit, or no size, has none" do
    %w[piece roll bottle can].each do |unit|
      supply = item(unit:, pack_size: 4, pack_unit: "piece")
      assert supply.valid?
      assert_equal [ nil, nil ], [ supply.pack_size, supply.pack_unit ]
    end
    supply = item(pack_size: "", pack_unit: "roll")
    assert supply.valid?
    assert_nil supply.pack_unit
    assert_not supply.packed?
  end

  test "a size of 1, 1000 or a fraction, or another kind of inside, is refused" do
    [ 1, 1000, 2.5 ].each { assert_not item(pack_size: it).valid?, it.to_s }
    assert_not item(pack_size: 4, pack_unit: "pack").valid?
  end
end
