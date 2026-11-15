# The forwarding address's setup emails and who may forward: the owner only
class ForwardingInboxPolicy < ApplicationPolicy
  def manage? = membership&.owner? || false
  alias_method :setup_email?, :manage?
  alias_method :add_forwarder?, :manage?
  alias_method :remove_forwarder?, :manage?
end
