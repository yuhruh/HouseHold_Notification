# The service worker confirms it showed a reminder (PRD §6). Unauthenticated and CSRF-exempt on
# purpose (the session may have expired); the single-use token is the only credential.
class PushReceiptsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection
  rate_limit to: 60, within: 1.minute

  def create
    attempt = DeliveryAttempt.find_by(receipt_token_digest: Digest::SHA256.hexdigest(params[:token].to_s), received_at: nil)
    return head(:not_found) unless attempt

    now = Time.current
    DeliveryAttempt.transaction do
      attempt.update!(status: "received", received_at: now)
      delivery = attempt.reminder_delivery
      delivery.update!(status: "sent", sent_at: now, error: nil) unless delivery.sent?
      PushSubscription.where(id: attempt.push_subscription_id).update_all(last_receipt_at: now)
    end
    head :no_content
  end
end
