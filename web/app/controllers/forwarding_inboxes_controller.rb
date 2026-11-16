# The "Set up forwarding" steps shared by the Electricity and Water pages: the owner sends (or
# resends) the setup email to a forwarder, adds an email that forwards (and sends it the setup
# email), or removes one. Goes back to the page it came from (`from`: electricity or water).
class ForwardingInboxesController < ApplicationController
  include HouseholdScoped
  before_action :set_inbox
  # Each of these sends an email to an address the owner typed
  rate_limit to: 10, within: 1.hour, only: %i[setup_email add_forwarder], by: -> { Current.user.id }, with: -> { back(alert: t("auth.rate_limited")) }

  # Send (or resend) the setup email to one of the forwarders
  def setup_email
    email = submitted_email
    return back(alert: t(".unknown")) unless @inbox.forwarder?(email)
    return back(alert: t(".too_soon", email:)) if @inbox.setup_sent_recently?(email)

    send_setup(email)
    back(notice: t(".sent", email:))
  end

  # Add an email that forwards, and send it the setup email
  def add_forwarder
    email = submitted_email
    return back(alert: t(".already", email:)) if @inbox.forwarder?(email)

    @inbox.allowed_senders += [ email ]
    return back(alert: @inbox.errors.full_messages.to_sentence) unless @inbox.save

    send_setup(email)
    back(notice: t(".added", email:))
  end

  # Members are always allowed; only an added email is removed
  def remove_forwarder
    email = submitted_email
    if @inbox.allowed_senders.include?(email)
      @inbox.update!(allowed_senders: @inbox.allowed_senders - [ email ], setup_emails_sent: @inbox.setup_emails_sent.except(email))
    end
    back(notice: t(".removed", email:))
  end

  private

  def set_inbox
    @inbox = Current.household.forwarding_inbox
    authorize(@inbox || ForwardingInbox)
    back unless @inbox&.address
  end

  def submitted_email = params.expect(:email).to_s.strip.downcase

  def send_setup(email)
    ForwardingSetupMailer.with(inbox: @inbox, email:, added_by: Current.user, locale: I18n.locale.to_s).setup.deliver_later
    @inbox.setup_sent!(email)
  end

  def back(**flash)
    page = params[:from] == "water" ? :household_water_account_path : :household_electricity_account_path
    redirect_to public_send(page, Current.household, anchor: "forwarding-setup"), **flash
  end
end
