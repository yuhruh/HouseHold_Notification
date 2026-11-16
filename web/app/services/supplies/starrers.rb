module Supplies
  # Whose star is it: the people who can star in a household (its owner, then the co-owners in the
  # order they joined), each with a colour (the owner amber, then teal, violet, rose…) and an initial,
  # so a star never says who by colour alone. A star of someone who is no longer one of them doesn't count
  class Starrers
    COLORS = %w[amber teal violet rose sky lime].freeze
    Person = Data.define(:user, :color, :initial, :name)

    attr_reader :people

    def initialize(household)
      @household = household
      members = household.memberships.where(role: %w[owner co_owner]).includes(:user)
      users = members.sort_by { [ it.owner? ? 0 : 1, it.created_at, it.id ] }.map(&:user)
      names = users.map { it.display_name.presence || it.email_address.to_s }
      firsts = names.map { it.first.to_s.upcase }
      @people = users.each_with_index.map do |user, index|
        # two people with the same first letter get two letters each
        initial = firsts.count(firsts[index]) > 1 ? names[index].first(2).capitalize : firsts[index]
        Person.new(user:, color: COLORS[index % COLORS.size], initial:, name: names[index])
      end
      @by_id = @people.index_by { it.user.id }
    end

    def several? = people.size > 1

    def person(user) = @by_id[user&.id]

    # From a link's `by` parameter
    def find(id) = @by_id[id.to_s.to_i]

    # The people whose star a supply has, in the order they joined
    def of(supply) = people.select { |person| starred_by?(supply, person.user) }

    def starred?(supply) = supply.favorites.any? { @by_id.key?(it.user_id) }

    def starred_by?(supply, user) = @by_id.key?(user&.id) && supply.favorites.any? { it.user_id == user.id }

    # Their stars on the household's items in use
    def stars = SupplyFavorite.where(supply: @household.supplies.active, user_id: @by_id.keys)
  end
end
