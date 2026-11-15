module Utilities
  # Reads what members' Gmail forwarded to the ledgers' addresses (ElectricityAccount#inbox_address)
  # and decides what each message is. Every message is labelled handled, whatever it is; what it
  # did (or why it was ignored) goes in the account's activity.
  #
  # - Gmail's forwarding confirmation (someone added the address in Gmail): signed by Google, with a
  #   confirmation link. When a member (or an allowed sender) asked, the link is kept so the
  #   Electricity page can show a Confirm button.
  # - A 台電 email, accepted only when it's one of:
  #     a. forwarded by a Gmail filter: From @taipower.com.tw (not failing DKIM/DMARC), sent on by
  #        "<member>+caf_=…@gmail.com", which Gmail's own SPF check on arrival passed
  #     b. forwarded by hand: From a member (signed by their mail provider), with a forwarded
  #        message from @taipower.com.tw inside
  #   Accepted ones are labelled BILLS and read by Utilities::Taipower::Reader, which writes the bill
  #   into the ledger. Only (a) counts as "the filter works".
  class ForwardedMail
    TOKEN = /\+h(\d+)-([a-z0-9]{10})@/i
    GOOGLE_FORWARDING = "forwarding-noreply@google.com".freeze
    TAIPOWER = /(\A|\.)taipower\.com\.tw\z/i
    CONFIRM_LINK = %r{https://mail-settings\.google\.com/mail/vf-[^\s<>"]+}
    EMAIL = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/
    # The header Gmail (or Outlook, Apple Mail) puts above a forwarded message, in English or Chinese
    FORWARDED_FROM = /^\s*(?:\*\s*)?(?:From|寄件者|寄件人|發件人)\s*[:：]\s*\*?[^\n]*?@((?:[\w-]+\.)*taipower\.com\.tw)\b/i
    LINK_KEPT = 7.days

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

    # :confirm, :bill, :ignored, or :unknown (no ledger's address on it)
    def call
      @account = find_account or return :unknown
      result = from == GOOGLE_FORWARDING ? confirmation : forwarded_bill
      @account.save!
      Taipower::Reader.call(@account, @mail) if result == :bill
      result
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

    # Gmail's own message: "x@gmail.com has requested to automatically forward mail to your email
    # address …", with a confirmation link (older ones also had a code)
    def confirmation
      return ignore("not_authentic", from) unless signed_by?(/\A(.*\.)?google\.com\z/)

      text = "#{@mail.subject}\n#{body_text}"
      requester = text.scan(EMAIL).map(&:downcase).find { it != GOOGLE_FORWARDING && !it.match?(TOKEN) }
      link = text[CONFIRM_LINK]
      code = @mail.subject.to_s[/\(#(\d{6,12})\)/, 1]
      return ignore("no_confirmation", nil) unless requester && (link || code)
      return ignore("not_member", requester) unless allowed?(requester)

      @account.assign_attributes(forwarding_link: link, forwarding_code: code, forwarding_from: requester, forwarding_code_at: Time.current)
      note("forwarding_request", requester)
      :confirm
    end

    def forwarded_bill
      if from.split("@").last.to_s.match?(TAIPOWER)
        return ignore("not_authentic", from) if failed_authentication?

        who = filter_forwarder or return ignore("unknown_forwarder", nil)
        return ignore("not_member", who) unless allowed?(who)

        @account.last_success_at = Time.current
        note("received", who)
      elsif allowed?(from)
        return ignore("not_authentic", from) unless signed_by?(/\A(.*\.)?#{Regexp.escape(from.split("@").last)}\z/i)
        return ignore("not_taipower_forward", from) unless body_text.match?(FORWARDED_FROM)

        note("received_by_hand", from)
      else
        return ignore("not_taipower", from.presence || "?")
      end
      :bill
    end

    def note(kind, detail) = @account.add_activity([ { "kind" => kind, "detail" => detail } ])

    # reason: a key under utilities.forwarded_mail in the locales
    def ignore(reason, detail)
      @account.add_activity([ { "kind" => "ignored", "reason" => reason, "detail" => detail } ])
      :ignored
    end

    # The member's Gmail whose filter forwarded it, from the envelope sender Gmail uses for filter
    # forwarding ("member+caf_=dest=gmail.com@gmail.com"), and only when Gmail's SPF check on arrival
    # passed for it
    def filter_forwarder
      sender = header_values("Return-Path").first.to_s.delete("<> ").downcase
      local = sender[/\A(.+?)\+caf_=.*@gmail\.com\z/, 1]
      "#{local}@gmail.com" if local && google_results.match?(/\bspf=pass\b[^;]*smtp\.mailfrom="?#{Regexp.escape(sender)}"?/i)
    end

    def allowed?(email)
      emails = @account.household.users.map(&:email_address) + @account.allowed_senders
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

    def signed_by?(domain)
      google_results.scan(/\bdkim=pass\b[^;]*header\.(?:i|d)=@?([\w.-]+)/i).flatten.any? { it.match?(domain) }
    end

    def failed_authentication? = google_results.match?(/\b(dkim|dmarc)=fail\b/i)

    def header_values(name) = Array(@mail.header[name]).map { it.respond_to?(:value) ? it.value : it.to_s }

    def body_text
      @body_text ||= begin
        part = @mail.multipart? ? (@mail.text_part || @mail.html_part) : @mail
        part&.decoded.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      rescue Mail::UnknownEncodingType, Encoding::Error
        ""
      end
    end
  end
end
