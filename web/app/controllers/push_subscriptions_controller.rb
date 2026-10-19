# This browser subscribes (from a tap on "Enable notifications") or a device is removed (PRD §13, §16)
class PushSubscriptionsController < ApplicationController
  def create
    subscription = PushSubscription.subscribe!(user: Current.user, session: Current.session,
      params: params.require(:subscription).permit(:endpoint, keys: %i[p256dh auth]), user_agent: request.user_agent)
    render json: { id: subscription.id, label: subscription.device_label }, status: :created
  rescue ActionController::ParameterMissing, KeyError, ActiveRecord::RecordInvalid
    head :unprocessable_content
  end

  # "Disable on this browser": the browser knows its endpoint, not our id
  def destroy_current
    Current.user.push_subscriptions.where(endpoint: params.require(:endpoint)).destroy_all
    head :no_content
  end

  def destroy
    Current.user.push_subscriptions.find(params[:id]).destroy!
    respond_to do |format|
      format.html { redirect_to account_path(anchor: "devices"), notice: t(".removed") }
      format.json { head :no_content }
    end
  end
end
