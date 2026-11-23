module Supplies
  # Just restocked while some was still left: which batch to use first, for the line under "Saved…".
  # Nothing to say (nil) unless other stock is still left and at least one of the two has an expiry
  # date. `older` is the batch left from before that is used first.
  # - :new_first: the new purchase expires before what was left (or what was left has no date)
  # - :old_first: what was left expires first, and the new one has a date too
  # - :old_still_first: the new one has no date, so the dated stock from before stays first
  class UseFirst
    Note = Data.define(:kind, :batch, :older)

    def self.call(supply, purchase) = new(supply, purchase).call

    def initialize(supply, purchase)
      @supply, @purchase = supply, purchase
    end

    def call
      batches = @supply.forecast.brands.batches
      batch = batches.find { it.purchase&.id == @purchase.id }
      older = batches.find { it.purchase&.id != @purchase.id }
      return unless batch && older && (batch.expires_on || older.expires_on)

      kind = if batch.first then :new_first
      elsif batch.expires_on then :old_first
      else :old_still_first
      end
      Note.new(kind:, batch:, older:)
    end
  end
end
