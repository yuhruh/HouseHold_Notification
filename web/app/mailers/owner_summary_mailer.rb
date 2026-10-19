class OwnerSummaryMailer < ApplicationMailer
  def summary
    @household, @lines = params[:household], params[:lines]
    I18n.with_locale(params[:owner].locale.presence || I18n.default_locale) do
      mail to: params[:owner].email_address, subject: params[:title]
    end
  end
end
