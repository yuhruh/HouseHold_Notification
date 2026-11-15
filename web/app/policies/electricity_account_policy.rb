# Ledger settings › Electricity: the owner and co-owners see it (the co-owner may be the one who
# sets up forwarding in Gmail); only the owner changes or disconnects it
class ElectricityAccountPolicy < ApplicationPolicy
  def show? = membership&.can_write? || false
  def manage? = membership&.owner? || false
  alias_method :update?, :manage?
  alias_method :destroy?, :manage?
  alias_method :setup_email?, :manage?
  alias_method :add_forwarder?, :manage?
  alias_method :remove_forwarder?, :manage?
end
