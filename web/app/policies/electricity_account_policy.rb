# Ledger settings › Electricity (and › Water, WaterAccountPolicy): the owner and co-owners see it
# (the co-owner may be the one who sets up forwarding in Gmail); only the owner changes or
# disconnects it
class ElectricityAccountPolicy < ApplicationPolicy
  def show? = membership&.can_write? || false
  def manage? = membership&.owner? || false
  alias_method :update?, :manage?
  alias_method :destroy?, :manage?
end
