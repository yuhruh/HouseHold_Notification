# My Account (PRD §13): profile, email, password, sign-in methods, sessions, households, danger zone
class AccountsController < ApplicationController
  def show
    @user = Current.user
  end

  def update
    @user = Current.user
    if @user.update(params.expect(user: %i[display_name locale time_zone reminder_hour]).tap { |p| p[:locale] = p[:locale].presence })
      redirect_to account_path, notice: t(".saved")
    else
      render :show, status: :unprocessable_content
    end
  end
end
