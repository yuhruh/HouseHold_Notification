# PRD §12: every member sees records; owners and co-owners change them
class RecordPolicy < ApplicationPolicy
  def show? = membership.present?
  def write? = membership&.can_write? || false
  alias_method :index?, :show?
  alias_method :new?, :write?
  alias_method :create?, :write?
  alias_method :edit?, :write?
  alias_method :update?, :write?
  alias_method :destroy?, :write?
  alias_method :restart_reminders?, :write?
  alias_method :done?, :write?
end
