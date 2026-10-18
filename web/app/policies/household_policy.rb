# PRD §12 role table
class HouseholdPolicy < ApplicationPolicy
  def show? = membership.present?
  def write? = membership&.can_write? || false
  def manage? = membership&.owner? || false
  alias_method :manage_members?, :manage?
end
