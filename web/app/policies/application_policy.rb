# The Pundit "user" is the Current.membership, so every policy knows the role in this household.
class ApplicationPolicy
  attr_reader :membership, :record

  def initialize(membership, record)
    @membership = membership
    @record = record
  end
end
