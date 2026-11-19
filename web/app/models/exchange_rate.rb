# What one unit of a currency was worth in another on a day, as a rate service answered
# (Supplies::ExchangeRateLookup). Public facts only, shared by every household.
#
# rated_on is the day asked about; published_on the day the answer is for, which is earlier when
# that day's rate isn't out yet. Such an answer is asked for again after a while; one for its own
# day, or for a day long past, is kept for good.
class ExchangeRate < ApplicationRecord
  RECHECK_AFTER = 6.hours
  SETTLED_AFTER_DAYS = 7

  def settled? = published_on >= rated_on || fetched_at.to_date > rated_on + SETTLED_AFTER_DAYS
  def fresh? = settled? || fetched_at > RECHECK_AFTER.ago
end
