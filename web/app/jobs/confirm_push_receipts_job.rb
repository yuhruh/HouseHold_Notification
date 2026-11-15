# Hourly (PRD §6): a push no device confirmed within 24h is failed (an asynchronous failure); the
# owner hears about it in the next daily summary. A "bill paid" or supplies push no device confirmed
# within RECEIPT_WAIT is sent by email instead.
class ConfirmPushReceiptsJob < ApplicationJob
  queue_as :default

  def perform
    ReminderDelivery.awaiting_receipt.where(dispatched_at: ...Reminders::PushSender::TTL.ago).find_each do |delivery|
      ReminderDelivery.transaction do
        delivery.delivery_attempts.accepted.each do |attempt|
          label = PushSubscription.find_by(id: attempt.push_subscription_id)&.device_label || "device"
          attempt.update!(error: "#{label}: #{I18n.t('reminders.push.no_receipt', locale: :en)}")
        end
        delivery.update!(status: "failed", failed_at: Time.current, owner_notified_at: nil,
          error: I18n.t("reminders.push.no_receipt", locale: :en))
      end
    end
    email_unconfirmed("bills_paid", NotifyBillsPaidJob)
    email_unconfirmed("supplies", SupplyAlertsJob)
  end

  private

  def email_unconfirmed(kind, job)
    received = DeliveryAttempt.received.where.not(notification_id: nil).select(:notification_id)
    Notification.where(kind:, fallback_emailed_at: nil, created_at: ...job::RECEIPT_WAIT.ago)
      .where(id: DeliveryAttempt.accepted.select(:notification_id)).where.not(id: received)
      .includes(:user).find_each do |notification|
        job.email_fallback!(notification)
      rescue StandardError => e
        Rails.error.report(e, context: { notification_id: notification.id })
      end
  end
end
