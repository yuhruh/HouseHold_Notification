# PRD §12: owners and co-owners edit categories and their import aliases; everyone sees them
class CategoryPolicy < ApplicationPolicy
  def index? = membership.present?
  def write? = membership&.can_write? || false
  alias_method :new?, :write?
  alias_method :create?, :write?
  alias_method :edit?, :write?
  alias_method :update?, :write?
  alias_method :archive?, :write?
  alias_method :destroy?, :write?
  alias_method :destroy_alias?, :write?
end
