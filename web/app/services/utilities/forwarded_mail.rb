module Utilities
  # Reads what members' Gmail forwarded to the ledgers' addresses (ForwardingInbox#address) and
  # decides what each message is. Every message is labelled handled, whatever it is; what it did
  # (or why it was ignored) goes in the activity of the account it's for (or, when that isn't
  # clear, of each of the ledger's mail accounts).
  #
  # - Gmail's forwarding confirmation (someone added the address in Gmail): signed by Google, with a
  #   confirmation link. When a member (or an allowed sender) asked, the link is kept so the
  #   Electricity and Water pages can show a Confirm button.
  # - A 台電 or 台水 email (COMPANIES), accepted only when it's one of:
  #     a. forwarded by a Gmail filter: From the company's domain (not failing DKIM/DMARC), sent on
  #        by "<member>+caf_=…@gmail.com", which Gmail's own SPF check on arrival passed
  #     b. forwarded by hand: From the owner or a co-owner (signed by their mail provider), with a
  #        forwarded message from the company's domain inside. What's quoted inside can't be
  #        checked, so it's taken only from someone who may edit the ledger anyway; a viewer or an
  #        added email forwards with a filter (a)
  #   and only when the ledger has turned that company on. Accepted ones are labelled for the
  #   company and read by its reader, which writes the bill into the ledger. Only (a) counts as
  #   "the filter works".
  class ForwardedMail
    TOKEN = /\+h(\d+)-([a-z0-9]{10})@/i
    GOOGLE_FORWARDING = "forwarding-noreply@google.com".freeze
    # Each company: its email domain, the ledger's account for it, and the reader of its emails
    COMPANIES = {
      taipower: { name: "台電", domain: /(\A|\.)taipower\.com\.tw\z/i, account: :electricity_account, reader: "Utilities::Taipower::Reader" },
      water: { name: "台水", domain: /(\A|\.)water\.gov\.tw\z/i, account: :water_account, reader: "Utilities::TaiwanWater::Reader" }
    }.freeze
    CONFIRM_LINK = %r{https://mail-settings\.google\.com/mail/vf-[^\s<>"]+}
    EMAIL = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/
    # The header Gmail (or Outlook, Apple Mail) puts above a forwarded message, in English or Chinese
    FORWARDED_FROM = /^\s*(?:\*\s*)?(?:From|寄件者|寄件人|發件人)\s*[:：]\s*\*?[^\n]*?@((?:[\w-]+\.)+[a-z]{2,})\b/i

    def self.call(inbox: Inbox.connect)
      return [] unless inbox && ForwardingInbox.mailbox

      inboxes = ForwardingInbox.includes(household: [ { memberships: :user }, :electricity_account, :water_account ]).index_by(&:inbox_token)
      return [] if inboxes.empty?

      inbox.unprocessed(inboxes.values.filter_map(&:address)).map do |id|
        forwarded = new(Mail.new(inbox.raw(id)), inboxes)
        result = forwarded.call
        inbox.done!(id, bill: (forwarded.company if result == :bill))
        result
      rescue *Inbox::UNAVAILABLE
        raise # Gmail itself can't be reached: stop here and read everything again next time
      rescue StandardError => e
        # One message that can't be handled must not hold up every ledger's mail: it's reported,
        # labelled handled like any other, and what it left half-changed is dropped
        Rails.error.report(e, context: { gmail_message_id: id })
        forwarded&.discard_changes
        inbox.done!(id)
        :failed
      end
    end

    # The company of an accepted bill email (a COMPANIES key)
    attr_reader :company

    def initialize(mail, inboxes)
      @mail, @inboxes = mail, inboxes
    end

    # After a failure: the ledger's address and accounts as they are in the database again, because
    # they're shared with the messages read after this one
    def discard_changes
      @inbox&.reload
    rescue ActiveRecord::RecordNotFound
      nil
    end

    # :confirm, :bill, :ignored, or :unknown (no ledger's address on it)
    def call
      @inbox = find_inbox or return :unknown
      result = from == GOOGLE_FORWARDING ? confirmation : forwarded_bill
      @inbox.save!
      @inbox.mail_accounts.each { it.save! if it.changed? }
      COMPANIES.fetch(@company)[:reader].constantize.call(@account, @mail) if result == :bill
      result
    end

    # The address it was delivered to names the ledger: "+h<household id>-<token>@"
    def find_inbox
      values = header_values("Delivered-To") + header_values("X-Forwarded-To") + Array(@mail.to)
      values.each do |value|
        household_id, token = value.to_s[TOKEN, 1], value.to_s[TOKEN, 2]&.downcase
        inbox = @inboxes[token]
        return inbox if inbox && inbox.household_id == household_id.to_i
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

      @inbox.assign_attributes(forwarding_link: link, forwarding_code: code, forwarding_from: requester, forwarding_code_at: Time.current)
      note("forwarding_request", requester)
      :confirm
    end

    def forwarded_bill
      if (@company = company_of(from.split("@").last))
        @account = account_for(@company)
        return ignore("not_authentic", from) if failed_authentication?

        who = filter_forwarder or return ignore("unknown_forwarder", nil)
        return ignore("not_member", who) unless allowed?(who)
        return ignore("not_turned_on", nil) unless @account

        @account.last_success_at = Time.current
        note("received", who)
      elsif allowed?(from)
        return ignore("not_authentic", from) unless signed_by?(/\A(.*\.)?#{Regexp.escape(from.split("@").last)}\z/i)
        return ignore("by_hand_not_editor", from) unless editor?(from)

        @company = body_text.scan(FORWARDED_FROM).flatten.filter_map { company_of(it) }.first
        return ignore("not_taipower_forward", from) unless @company
        return ignore("not_turned_on", nil) unless (@account = account_for(@company))

        note("received_by_hand", from)
      else
        return ignore("not_taipower", from.presence || "?")
      end
      :bill
    end

    def company_of(domain) = COMPANIES.find { |_, company| domain.to_s.match?(company[:domain]) }&.first

    def account_for(company) = @inbox.household.public_send(COMPANIES.fetch(company)[:account])

    # The account the email is for, or else each of the ledger's mail accounts
    def noted_by = @account ? [ @account ] : @inbox.mail_accounts

    def note(kind, detail) = noted_by.each { it.add_activity([ { "kind" => kind, "detail" => detail } ]) }

    # reason: a key under utilities.forwarded_mail in the locales. A company the ledger hasn't
    # turned on is noted on the other accounts, named.
    def ignore(reason, detail)
      detail = COMPANIES.fetch(@company)[:name] if reason == "not_turned_on"
      noted_by.each { it.add_activity([ { "kind" => "ignored", "reason" => reason, "detail" => detail } ]) }
      :ignored
    end


    # The member's Gmail whose filter forwarded it, from the envelope sender Gmail uses for filter
    # forwarding ("member+caf_=dest=gmail.com@gmail.com"), and only when Gmail's SPF check on arrival
    # passed for it
    def filter_forwarder
      local = authentication.spf_sender.to_s[/\A([\w.-]+)\+caf_=[\w.=+-]*@gmail\.com\z/, 1]
      "#{local}@gmail.com" if local
    end

    def allowed?(email) = same_address?(email, member_emails + @inbox.allowed_senders)

    # The owner or a co-owner: someone who may add and change the ledger's bills themselves
    def editor?(email) = same_address?(email, member_emails(&:can_write?))

    def member_emails(&role) = @inbox.household.memberships.select { role.nil? || role.call(it) }.filter_map { it.user.email_address }

    def same_address?(email, emails) = emails.map { canonical(it) }.include?(canonical(email))

    # Gmail ignores dots and anything after "+" in its own addresses
    def canonical(email)
      local, domain = email.to_s.downcase.split("@", 2)
      return email.to_s.downcase unless domain.in?(%w[gmail.com googlemail.com])

      "#{local.split("+").first.delete(".")}@gmail.com"
    end

    # What Gmail's own checks on arrival found
    def authentication = @authentication ||= AuthenticationResults.of(@mail)

    def signed_by?(domain) = authentication.dkim_domains.any? { it.match?(domain) }

    def failed_authentication? = authentication.failed?

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
