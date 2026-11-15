# Everyone in the household sees supplies; owners and co-owners add, count, restock and edit them
class SupplyPolicy < ApplicationPolicy
  def index? = membership.present?
  alias_method :show?, :index?
  def write? = membership&.can_write? || false
  alias_method :new?, :write?
  alias_method :create?, :write?
  alias_method :edit?, :write?
  alias_method :update?, :write?
  alias_method :archive?, :write?
end
