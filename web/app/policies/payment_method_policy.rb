# PRD §12: owners and co-owners manage payment methods; everyone sees them
class PaymentMethodPolicy < ApplicationPolicy
  def index? = membership.present?
  def write? = membership&.can_write? || false
  alias_method :new?, :write?
  alias_method :create?, :write?
  alias_method :edit?, :write?
  alias_method :update?, :write?
  alias_method :archive?, :write?
  alias_method :from_notes?, :write?
  alias_method :assign_from_notes?, :write?
end
