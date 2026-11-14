module Utilities
  # The app's own Gmail mailbox (the reminder sender, Rails credentials `gmail`), read through the
  # Gmail API with gmail.modify. Members' Gmail forwards 台電's emails to plus-addresses of it (see
  # ElectricityAccount#inbox_address). A message handled is labelled PROCESSED and marked read, so
  # it isn't read twice; a 台電 email also gets BILLS, the ones Utilities::ForwardedMail hands on to
  # the bill reader.
  class Inbox
    PROCESSED = "Household Tracker/Processed".freeze
    BILLS = "Household Tracker/台電".freeze
    PAGE = 100

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

    # Ids of messages not handled yet that were delivered to any of `addresses`, oldest first
    def unprocessed(addresses)
      return [] if addresses.empty?

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

    # The message as sent (RFC 822)
    def raw(id) = @service.get_user_message("me", id, format: "raw").raw

    def done!(id, bill: false)
      add = [ label_id(PROCESSED), (label_id(BILLS) if bill) ].compact
      @service.modify_message("me", id, Google::Apis::GmailV1::ModifyMessageRequest.new(add_label_ids: add, remove_label_ids: [ "UNREAD" ]))
    end

    private

    # Gmail search writes a label's spaces and slashes as dashes
    def label_query(name) = name.downcase.tr(" /", "--")

    def label_id(name)
      @labels ||= Array(@service.list_user_labels("me").labels).to_h { [ it.name, it.id ] }
      @labels[name] ||= @service.create_user_label("me", Google::Apis::GmailV1::Label.new(name:, label_list_visibility: "labelShow", message_list_visibility: "show")).id
    end
  end
end
