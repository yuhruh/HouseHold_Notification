# What a public product database said about a barcode (or that none knew it), kept for a while so
# a second scan doesn't ask again. Public product facts only, shared by every household.
class ProductLookup < ApplicationRecord
  FOUND_TTL = 30.days
  NOT_FOUND_TTL = 1.day

  def found? = name.present?
  def fresh? = fetched_at > (found? ? FOUND_TTL : NOT_FOUND_TTL).ago
end
