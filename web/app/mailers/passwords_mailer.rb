class PasswordsMailer < ApplicationMailer
  def reset
    @user = params[:user]
    mail subject: t(".subject"), to: @user.email_address
  end
end
