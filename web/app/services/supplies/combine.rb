module Supplies
  # Two items that are the same thing (one saved per product: "Promise Volume Shampoo", "PDRN Care
  # Shampoo") become one: `source` moves into `target` and becomes a brand of it. Purchases, counts,
  # old prices, barcodes, stars and what receipts remembered go along; a purchase with no product
  # named takes the source's name, and the target remembers that name (former_names) so a receipt
  # line with it is matched to the target. The target keeps its name, category, unit and settings.
  #
  # The two histories become one timeline. At every purchase and count, the other item still had
  # what it last knew, so that is added to the number the event recorded: the counts add up and the
  # forecast sees only the usage each item really had. Every count also gets each brand's number
  # (by_product), so the brands keep the shares they had.
  class Combine
    def self.call(source, into:, user:) = new(source, into, user).call

    def initialize(source, target, user)
      @source, @target, @user = source, target, user
    end

    def call
      raise ArgumentError, "an item can't be combined with itself" if @source.id == @target.id
      raise ArgumentError, "both items must be in the same ledger" if @source.household_id != @target.household_id

      Supply.transaction do
        [ @source, @target ].sort_by(&:id).each(&:lock!)
        @brand = (@source.name unless @source.name == @target.name)
        brands = { @source.id => Brands.new(@source), @target.id => Brands.new(@target) }
        shares = ->(supply, time = nil) { named(brands[supply.id].known_at(time), supply) }
        expected = add(shares.(@source), shares.(@target))
        plan = (events(@source) + events(@target)).map do |event|
          mine, other = event.supply_id == @source.id ? [ @source, @target ] : [ @target, @source ]
          [ event, shares.(mine, event.at), shares.(other, event.at) ]
        end

        plan.each { |event, mine, other| move(event, mine, other) }
        move_the_rest
        @source.reload.destroy!
        @target.update!(former_names: former_names)
        @target.update!(guess_days_per_unit: @source.guess_days_per_unit) if @target.guess_days_per_unit.nil? && @source.guess_days_per_unit
        StockChanged.call(@target)
        pin(expected)
        @target
      end
    end

    private

    def events(supply) = supply.purchases.to_a + supply.counts.to_a

    # The source's name (and the names of items combined into it before) stay known to the target, so
    # a receipt line with one is still matched here even when no purchase, price or barcode carries it
    def former_names = (@target.former_names + [ @source.name ] + @source.former_names).uniq - [ @target.name ]

    # The source's stock with no product named is now the brand called after it
    def key(name, supply) = supply.id == @source.id && name.to_s.empty? ? Brands.key(@brand) : name.to_s

    def named(shares, supply) = shares.each_with_object(Hash.new(0)) { |(name, left), all| all[key(name, supply)] += left }

    def add(one, other) = one.merge(other) { |_, a, b| a + b }

    def move(event, mine, other)
      theirs = other.values.sum
      from_source = event.supply_id == @source.id
      if event.is_a?(SupplyPurchase)
        changes = { left_before: event.left_before + theirs }
        changes.merge!(supply_id: @target.id, product_name: event.product_name || @brand) if from_source
      else
        changes = { level: event.level + theirs, by_product: add(mine, other) }
        changes.merge!(supply_id: @target.id, used_product: (key(event.used_product, @source) if event.used_product)) if from_source
      end
      event.update_columns(changes)
    end

    # Old prices and barcodes say which product they were; a star moves unless that person already
    # starred the target; a receipt line that meant the source now means the target
    def move_the_rest
      @source.prices.where(product_name: nil).update_all(product_name: @brand)
      @source.prices.update_all(supply_id: @target.id)
      @source.barcodes.where(product_name: nil).update_all(product_name: @brand)
      @source.barcodes.update_all(supply_id: @target.id)
      @source.favorites.where.not(user_id: @target.favorites.select(:user_id)).update_all(supply_id: @target.id)
      @source.household.receipt_item_matches.where(supply_id: @source.id).update_all(supply_id: @target.id)
    end

    # The brands' shares should be what the two items had. A purchase after the last count can still
    # shift them (what was used before it is taken from the brand bought first, now of both items):
    # then one count, a second after the last event so the forecast learns nothing from it, sets them
    def pin(expected)
      @target.reload
      return if Brands.new(@target).known_at == expected || expected.keys.any? { Brands.new(@target).keys.exclude?(it) }

      last = Timeline.new(@target).events.last
      @target.counts.create!(level: expected.values.sum, by_product: expected, counted_at: last.at + 1.second, created_by: @user)
      StockChanged.call(@target)
    end
  end
end
