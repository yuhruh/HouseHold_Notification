# One person's star on a supply. Owners and co-owners each have their own (Supplies::Starrers gives
# each a colour); an item is on Supplies › Favorites while any of them has a star on it
class SupplyFavorite < ApplicationRecord
  belongs_to :supply
  belongs_to :user
end
