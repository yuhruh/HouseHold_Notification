# Owners and co-owners add, rename and archive the ledger's supply categories; "Other" always stays
class SupplyCategoryPolicy < ApplicationPolicy
  def write? = membership&.can_write? || false
  alias_method :new?, :write?
  alias_method :create?, :write?
  alias_method :edit?, :write?
  alias_method :update?, :write?

  def archive? = write? && !record.fallback?
  alias_method :destroy?, :archive?
end
