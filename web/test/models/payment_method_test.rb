require "test_helper"

class PaymentMethodTest < ActiveSupport::TestCase
  def method(**attrs) = households(:home).payment_methods.new({ name: "Card", kind: "card" }.merge(attrs))

  test "only the last 4 digits are kept: a name holding a full card number is refused" do
    [ "4123456789015678", "4123 4567 8901 5678", "4123-4567-8901-5678", "Visa 4123 4567 8901 5678" ].each do |name|
      assert_not method(name:).valid?, name
    end
    [ "玉山 ubear", "CTBC 2024", "Card 1234 5678" ].each { |name| assert method(name:).valid?, name }
    assert_not method(last4: "123").valid?
    assert_equal "Card ··1234", method(last4: "1234").label
  end
end
