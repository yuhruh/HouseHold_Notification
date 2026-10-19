# Sends one email digest (PRD §6). Transient errors retry 3 times with backoff; a final failure
# marks the delivery failed and reports to Sentry. A revoked Gmail token fails at once and pings
# the reminder heartbeat's /fail (a system-wide, synchronous failure).
class DeliverReminderJob < ApplicationJob
  queue_as :default

  retry_on StandardError, attempts: 3, wait: :polynomially_longer do |job, error|
    job.fail_delivery(error)
  end

  def perform(delivery_id, resend: false)
    @delivery = ReminderDelivery.find_by(id: delivery_id)
    return unless @delivery&.email? && (@delivery.pending? || resend)

    @delivery.update!(attempts: @delivery.attempts + 1, dispatched_at: @delivery.dispatched_at || Time.current)
    ReminderMailer.with(delivery: @delivery).digest.deliver_now
    @delivery.update!(status: "sent", sent_at: Time.current, error: nil)
    @delivery.delivery_attempts.create!(channel: "email", status: "accepted", attempted_at: Time.current)
  rescue DeliveryMethods::GmailApi::AuthorizationError => e
    fail_delivery(e)
    Heartbeat.ping(ENV["REMINDER_HEARTBEAT_URL"], "/fail")
  end

  def fail_delivery(error)
    delivery = @delivery || ReminderDelivery.find_by(id: arguments.first)
    return unless delivery

    delivery.update!(status: "failed", failed_at: Time.current, error: error.message.first(250), owner_notified_at: nil)
    delivery.delivery_attempts.create!(channel: "email", status: "error", error: error.message.first(250), attempted_at: Time.current)
    Sentry.capture_exception(error) if defined?(Sentry)
  end
end
