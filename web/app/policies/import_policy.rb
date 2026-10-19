# PRD §12: owners and co-owners import and undo
class ImportPolicy < ApplicationPolicy
  def write? = membership&.can_write? || false
  alias_method :new?, :write?
  alias_method :create?, :write?
  alias_method :show?, :write?
  alias_method :commit?, :write?
  alias_method :undo?, :write?
end
