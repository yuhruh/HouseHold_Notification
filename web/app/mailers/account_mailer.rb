class AccountMailer < ApplicationMailer
  # Sent after the account is gone, so it takes plain values
  def deleted
    mail to: params[:email], subject: t(".subject")
  end
end
