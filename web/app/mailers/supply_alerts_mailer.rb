# The supplies digest, by email when the push couldn't reach a device (SupplyAlertsJob)
class SupplyAlertsMailer < ApplicationMailer
  def digest
    @notification = params[:notification]
    mail to: @notification.user.email_address, subject: @notification.title
  end
end
