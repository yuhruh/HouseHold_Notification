# Email + password sign-up. Always answers "check your email", so it never reveals whether an
# address has an account (PRD §10).
class RegistrationsController < ApplicationController
  include AuthPage

  allow_unauthenticated_access
  before_action :redirect_signed_in_user
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: t("auth.rate_limited") }

  def new
    # Prefilled from an invitation link (PRD §12a)
    @user = User.new(unconfirmed_email: params[:email])
  end

  def create
    @user = User.new(registration_params.merge(time_zone: User.valid_time_zone(params[:tz])))
    @user.errors.add(:unconfirmed_email, :blank) if @user.unconfirmed_email.blank?
    @user.errors.add(:password, :blank) if @user.password.blank?
    # Validate before looking the address up, so a bad password gets the same answer either way
    return render(:new, status: :unprocessable_content) unless @user.errors.empty? && @user.valid?

    locale = I18n.locale.to_s
    if existing = User.find_by(email_address: @user.unconfirmed_email)
      AuthMailer.with(user: existing, locale: existing.locale || locale).already_registered.deliver_later
    else
      @user.save!
      AuthMailer.with(user: @user, locale:).email_confirmation.deliver_later
    end
    render :check_email
  end

  private
    def registration_params
      params.expect(user: %i[ display_name unconfirmed_email password password_confirmation ])
    end
end
