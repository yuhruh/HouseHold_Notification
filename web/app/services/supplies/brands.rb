module Supplies
  # What is left of each brand of one item. The item still has one count, one usage rate and one
  # restock alert (Supply#level, Forecast); this only splits that count by the product named on each
  # purchase, so you can see and say which brand a bottle was.
  #
  # The item's purchases and counts are replayed in time order as lots, one per purchase:
  # - a purchase adds its quantity under its product ("" when none was named);
  # - −1 with a brand takes one from that brand, a count made brand by brand sets each brand;
  # - any other change (a plain count, what was left before a purchase) takes from the lot to use
  #   first. Stock no purchase explains goes to the brand bought last, or to the first brand bought
  #   when there was none yet.
  # The lot to use first is the one that expires first; lots with no expiry date come after those
  # with one, in the order they were bought (the same day: the one entered first).
  # `known` is a brand's share of the last count. `left` is its share of the number shown now: the
  # usage the forecast estimates since that count is also taken from the lot to use first, so the
  # brands always add up to the total on screen.
  class Brands
    NO_BRAND = "".freeze

    Lot = Struct.new(:key, :left, :purchase)
    # `purchase` is the one its stock to use first is from; `first` marks the brand to use first
    Brand = Data.define(:key, :name, :known, :left, :purchase, :first) do
      def named? = name.present?

      # When the stock of it to use first expires, if that purchase had a date
      def expires_on = purchase&.expires_on
    end

    def self.key(product_name) = product_name.to_s

    # A purchase's product was corrected on Edit: the counts that named the old one follow it,
    # unless another purchase still has that name
    def self.renamed(supply, from:, to:)
      from, to = key(from), key(to)
      return if from == to || supply.purchases.any? { key(it.product_name) == from }

      supply.counts.each do |count|
        changes = {}
        changes[:used_product] = to if count.used_product == from
        if count.by_product&.key?(from)
          numbers = count.by_product.dup
          numbers[to] = numbers[to].to_i + numbers.delete(from).to_i
          changes[:by_product] = numbers
        end
        count.update_columns(changes) if changes.any?
      end
    end

    def initialize(supply, forecast = supply.forecast)
      @supply = supply
      @forecast = forecast
    end

    # The brands with some left at the last count, the one to use first on top
    def list
      @list ||= begin
        shown = lots.map(&:dup)
        take(shown, shown.sum(&:left) - @forecast.on_hand_rounded)
        now = shown.group_by(&:key).transform_values { |mine| mine.sum(&:left) }
        use_first(lots).select { it.left.positive? }.group_by(&:key).each_with_index.map do |(key, mine), index|
          Brand.new(key:, name: key.presence, known: mine.sum(&:left), left: now.fetch(key, 0), purchase: mine.first.purchase, first: index.zero?)
        end
      end
    end

    # Two or more brands in stock: −1 asks which one, and the lists show each brand's number
    def several? = list.size > 1

    def find(key) = list.find { it.key == key.to_s }

    # Each brand's share of the last known count, or of the count as it stood at `time`:
    # product => how many (Supplies::Combine adds two items' shares together)
    def known_at(time = nil)
      at = time ? replay(events.select { it.at <= time }) : lots
      at.group_by(&:key).transform_values { |mine| mine.sum(&:left) }.select { |_, left| left.positive? }
    end

    # Every product this item was bought as: the names a brand-by-brand count may use
    def keys = @supply.purchases.reject(&:new_record?).map { self.class.key(it.product_name) }.uniq

    private

    def lots = @lots ||= replay(events)

    def replay(events)
      lots = []
      events.each do |event|
        if event.is_a?(SupplyPurchase)
          settle(lots, event.left_before)
          key = self.class.key(event.product_name)
          lots.each { it.key ||= key }
          add(lots, Lot.new(key, event.quantity, event))
        else
          if event.by_product.present?
            assign(lots, event.by_product)
          elsif event.used_product
            take(lots.select { it.key == event.used_product }, 1)
          end
          settle(lots, event.level)
        end
      end
      lots.each { it.key ||= NO_BRAND }
    end

    def events = @events ||= (@supply.purchases.to_a + @supply.counts.to_a).reject(&:new_record?).sort_by(&:at)

    # Lots stay in the order they were bought, not logged: a restock logged today for something
    # bought in September is still the older stock
    def add(lots, lot)
      later = lots.index { it.purchase && it.purchase.purchased_on > lot.purchase.purchased_on }
      lots.insert(later || lots.size, lot)
    end

    # The order stock is used in: lots with an expiry date by that date, then the rest as bought
    def use_first(lots)
      lots.each_with_index.sort_by { |lot, index| [ lot.purchase&.expires_on ? 0 : 1, lot.purchase&.expires_on, index ] }.map(&:first)
    end

    # Bring the lots to a count of the whole item: too many go from the lot to use first, extra ones
    # join the brand bought last
    def settle(lots, target)
      extra = lots.sum(&:left) - target
      return take(lots, extra) unless extra.negative?

      lot = lots.last || Lot.new(nil, 0, nil).tap { lots << it }
      lot.left -= extra
    end

    def take(lots, amount)
      use_first(lots).each do |lot|
        break unless amount.positive?
        used = [ lot.left, amount ].min
        lot.left -= used
        amount -= used
      end
    end

    # A count made brand by brand: each brand this item was bought as is set to its number (0 when
    # the count didn't list it); a name no purchase has is ignored
    def assign(lots, numbers)
      lots.group_by(&:key).each do |key, mine|
        extra = mine.sum(&:left) - numbers[key].to_i
        if extra.negative?
          mine.last.left -= extra
        else
          take(mine, extra)
        end
      end
    end
  end
end
