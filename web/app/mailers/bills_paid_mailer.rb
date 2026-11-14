# "Bill paid", by email when the push couldn't reach a device (NotifyBillsPaidJob)
class BillsPaidMailer < ApplicationMailer
  def paid
    @notification = params[:notification]
    mail to: @notification.user.email_address, subject: @notification.title
  end
end
