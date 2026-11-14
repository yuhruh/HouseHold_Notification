module Utilities
  # Reads what members' Gmail forwarded to the ledgers' addresses (ElectricityAccount#inbox_address)
  # and decides what each message is. Every message is labelled handled, whatever it is.
  #
  # - Gmail's forwarding confirmation (someone added the address in Gmail): its code is kept on the
  #   account so the Electricity page can show it.
  # - A 台電 email is accepted only when all of these hold; anything else is ignored and noted in
  #   the account's activity:
  #     1. it was sent by 台電 (From @taipower.com.tw, and not failing DKIM/DMARC)
  #     2. it came through a ledger member's Gmail (or one of the account's allowed senders): Gmail's
  #        filter forwarding sends it from "<member>+caf_=…@gmail.com", which Gmail's own SPF check
  #        on arrival must pass
  #   Accepted ones are labelled for the bill reader.
  class ForwardedMail
    TOKEN = /\+h(\d+)-([a-z0-9]{10})@/i
    GOOGLE_FORWARDING = "forwarding-noreply@google.com".freeze
    TAIPOWER = /(\A|\.)taipower\.com\.tw\z/i
    CODE_KEPT = 7.days

    def self.call(inbox: Inbox.connect)
      return [] unless inbox && ElectricityAccount.mailbox

      accounts = ElectricityAccount.where.not(inbox_token: nil).includes(household: :users).index_by(&:inbox_token)
      return [] if accounts.empty?

      inbox.unprocessed(accounts.values.filter_map(&:inbox_address)).map do |id|
        result = new(Mail.new(inbox.raw(id)), accounts).call
        inbox.done!(id, bill: result == :bill)
        result
      end
    end

    def initialize(mail, accounts)
      @mail, @accounts = mail, accounts
    end

    # :code, :bill, :ignored, or :unknown (no ledger's address on it)
    def call
      account = find_account or return :unknown
      return confirmation(account) if from == GOOGLE_FORWARDING

      reason, detail = rejection(account)
      account.last_success_at = Time.current unless reason
      account.add_activity([ reason ? { "kind" => "ignored", "reason" => reason, "detail" => detail } : { "kind" => "received", "detail" => forwarder } ])
      account.save!
      reason ? :ignored : :bill
    end

    # The address it was delivered to names the ledger: "+h<household id>-<token>@"
    def find_account
      values = header_values("Delivered-To") + header_values("X-Forwarded-To") + Array(@mail.to)
      values.each do |value|
        household_id, token = value.to_s[TOKEN, 1], value.to_s[TOKEN, 2]&.downcase
        account = @accounts[token]
        return account if account && account.household_id == household_id.to_i
      end
      nil
    end

    private

    def from = Array(@mail.from).first.to_s.downcase

    # Gmail's own message: "(#123456789) Gmail Forwarding Confirmation - Receive Mail from x@gmail.com"
    # (or the same in another language); the code is also in the body
    def confirmation(account)
      return :ignored unless authenticated?(dkim: /\A(.*\.)?google\.com\z/)

      text = "#{@mail.subject}\n#{body_text}"
      code = @mail.subject.to_s[/\(#(\d{6,12})\)/, 1] || text[/\b(\d{9})\b/, 1] or return :ignored
      mailbox = ElectricityAccount.mailbox.to_s.downcase
      requester = text.scan(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/).map(&:downcase).find { !it.start_with?(mailbox.split("@").first) && it != GOOGLE_FORWARDING }
      account.assign_attributes(forwarding_code: code, forwarding_from: requester, forwarding_code_at: Time.current)
      account.add_activity([ { "kind" => "forwarding_code", "detail" => requester.to_s } ])
      account.save!
      :code
    end

    # nil, or why it's ignored: [reason, detail] (see utilities.forwarded_mail in the locales)
    def rejection(account)
      domain = from.split("@").last.to_s
      return [ "not_taipower", from.presence || "?" ] unless domain.match?(TAIPOWER)
      return [ "not_authentic", from ] if failed_authentication?

      who = forwarder or return [ "unknown_forwarder", nil ]
      [ "not_member", who ] unless allowed?(account, who)
    end

    # The member's Gmail that forwarded it, from the envelope sender Gmail uses for filter forwarding
    # ("member+caf_=dest=gmail.com@gmail.com"), and only when Gmail's SPF check on arrival passed for it
    def forwarder
      @forwarder ||= begin
        sender = header_values("Return-Path").first.to_s.delete("<> ").downcase
        local = sender[/\A(.+?)\+caf_=.*@gmail\.com\z/, 1]
        "#{local}@gmail.com" if local && google_results.match?(/\bspf=pass\b[^;]*smtp\.mailfrom="?#{Regexp.escape(sender)}"?/i)
      end
    end

    def allowed?(account, email)
      emails = account.household.users.map(&:email_address) + account.allowed_senders
      emails.map { canonical(it) }.include?(canonical(email))
    end

    # Gmail ignores dots and anything after "+" in its own addresses
    def canonical(email)
      local, domain = email.to_s.downcase.split("@", 2)
      return email.to_s.downcase unless domain.in?(%w[gmail.com googlemail.com])

      "#{local.split("+").first.delete(".")}@gmail.com"
    end

    # The Authentication-Results Gmail added on arrival (the first one, from mx.google.com)
    def google_results
      @google_results ||= header_values("Authentication-Results").find { it.to_s.strip.start_with?("mx.google.com") }.to_s
    end

    def authenticated?(dkim:)
      google_results.scan(/\bdkim=pass\b[^;]*header\.(?:i|d)=@?([\w.-]+)/i).flatten.any? { it.match?(dkim) }
    end

    def failed_authentication? = google_results.match?(/\b(dkim|dmarc)=fail\b/i)

    def header_values(name) = Array(@mail.header[name]).map { it.respond_to?(:value) ? it.value : it.to_s }

    def body_text
      part = @mail.multipart? ? (@mail.text_part || @mail.html_part) : @mail
      part&.decoded.to_s
    rescue Mail::UnknownEncodingType, Encoding::Error
      ""
    end
  end
end
