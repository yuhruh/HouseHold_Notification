# The setup email the owner sends from Electricity or Water › Set up forwarding: this ledger's
# forwarding address (with a link to a page that copies it) and how to set up Gmail to send the
# companies' emails there. It names the companies the ledger has turned on (台電, 台水), and the
# Gmail filter that catches all of them.
class ForwardingSetupMailer < ApplicationMailer
  # Each company the email can name, by account type, and its Gmail filter term
  COMPANIES = { "ElectricityAccount" => [ "台電", "taipower.com.tw" ], "WaterAccount" => [ "台水", "water.gov.tw" ] }.freeze

  def setup
    @inbox = params[:inbox]
    @address = @inbox.address
    @copy_url = forwarding_address_url(token: @inbox.inbox_token)
    @owner = params[:added_by]&.display_name.presence || params[:added_by]&.email_address || "Household Tracker"
    companies = @inbox.mail_accounts.map { COMPANIES.fetch(it.type) }.presence || [ COMPANIES.fetch("ElectricityAccount") ]
    @companies = companies.map(&:first).to_sentence(two_words_connector: t(".and"), last_word_connector: t(".and"))
    domains = companies.map(&:last)
    @filter = domains.one? ? "from:#{domains.first}" : "from:(#{domains.join(" OR ")})"
    @several = domains.many?
    mail to: params[:email], subject: t(".subject", household: @inbox.household.name, companies: @companies)
  end
end
