# PRD §12: owners and co-owners manage templates; everyone sees them
class RecurringTemplatePolicy < ApplicationPolicy
  def index? = membership.present?
  def write? = membership&.can_write? || false
  alias_method :new?, :write?
  alias_method :create?, :write?
  alias_method :edit?, :write?
  alias_method :update?, :write?
  alias_method :destroy?, :write?
  alias_method :link?, :write?
end
