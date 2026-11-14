# Ledger settings › Gas account: the owner connects, changes and checks it
class GasAccountPolicy < ApplicationPolicy
  def manage? = membership&.owner? || false
  alias_method :show?, :manage?
  alias_method :update?, :manage?
  alias_method :destroy?, :manage?
  alias_method :check?, :manage?
end
