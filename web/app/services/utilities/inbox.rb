module Utilities
  # The app's own Gmail mailbox (the reminder sender, Rails credentials `gmail`), read through the
  # Gmail API with gmail.modify. Members' Gmail forwards 台電's and 台水's emails to plus-addresses
  # of it (see ForwardingInbox#address). A message handled is labelled PROCESSED and marked read, so
  # it isn't read twice; a bill email also gets its company's BILLS label, the ones
  # Utilities::ForwardedMail hands on to a bill reader. Then it's moved to Trash (Gmail empties it
  # after 30 days): the app keeps what it needs from it, and a bill sent again is matched to the one
  # already written (Utilities::BillSync), so nothing depends on the email staying.
  class Inbox
    PROCESSED = "Household Tracker/Processed".freeze
    BILLS = { taipower: "Household Tracker/台電", water: "Household Tracker/台水" }.freeze
    PAGE = 100
    # Ledgers' addresses named in one Gmail search. The search goes out in the request's URL, so one
    # naming every ledger's address would grow with each ledger added until Gmail refused it, and
    # then no ledger's mail would be read.
    ADDRESSES_PER_SEARCH = 20

    # Errors meaning the mailbox can't be read now (no read permission yet, revoked token, Gmail down)
    UNAVAILABLE = [ Google::Apis::Error, Signet::AuthorizationError ].freeze

    # nil where the app has no Gmail set up (development, tests)
    def self.connect
      config = Rails.application.credentials.gmail&.to_h&.symbolize_keys
      return unless config&.values_at(:client_id, :client_secret, :refresh_token)&.all?(&:present?)

      service = Google::Apis::GmailV1::GmailService.new
      service.authorization = DeliveryMethods::GmailApi.credentials(config, scope: DeliveryMethods::GmailApi::READ_SCOPE)
      new(service)
    end

    def initialize(service)
      @service = service
    end

    # Ids of messages not handled yet that were delivered to any of `addresses`, oldest first for
    # each address. Searched ADDRESSES_PER_SEARCH addresses at a time; a message delivered to
    # addresses in two searches is listed once.
    def unprocessed(addresses)
      return [] if addresses.empty?

      addresses.each_slice(ADDRESSES_PER_SEARCH).flat_map { unprocessed_for(it) }.uniq
    end

    # The message as sent (RFC 822)
    def raw(id) = @service.get_user_message("me", id, format: "raw").raw

    # bill: the company (a Utilities::ForwardedMail::COMPANIES key) of an accepted bill email;
    # trash: false keeps it in the mailbox (one that couldn't be handled, to look into). Labelled
    # first, so a message whose trashing fails still isn't read again.
    def done!(id, bill: nil, trash: true)
      add = [ label_id(PROCESSED), (label_id(BILLS.fetch(bill)) if bill) ].compact
      @service.modify_message("me", id, Google::Apis::GmailV1::ModifyMessageRequest.new(add_label_ids: add, remove_label_ids: [ "UNREAD" ]))
      @service.trash_user_message("me", id) if trash
    end

    private

    # One search: up to about PAGE * 5 ids, oldest first
    def unprocessed_for(addresses)
      query = "{#{addresses.map { "deliveredto:#{it}" }.join(" ")}} -label:#{label_query(PROCESSED)}"
      ids, token = [], nil
      loop do
        page = @service.list_user_messages("me", q: query, max_results: PAGE, page_token: token)
        ids.concat(Array(page.messages).map(&:id))
        token = page.next_page_token
        break if token.nil? || ids.size >= PAGE * 5
      end
      ids.reverse
    end

    # Gmail search writes a label's spaces and slashes as dashes
    def label_query(name) = name.downcase.tr(" /", "--")

    def label_id(name)
      @labels ||= Array(@service.list_user_labels("me").labels).to_h { [ it.name, it.id ] }
      @labels[name] ||= @service.create_user_label("me", Google::Apis::GmailV1::Label.new(name:, label_list_visibility: "labelShow", message_list_visibility: "show")).id
    end
  end
end
