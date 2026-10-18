namespace :gmail do
  desc "One-time OAuth for the household sender account; prints a refresh token for Rails credentials"
  task authorize: :environment do
    require "googleauth"
    require "googleauth/stores/file_token_store"

    config = DeliveryMethods::GmailApi.config
    client_id = Google::Auth::ClientId.new(config.fetch(:client_id), config.fetch(:client_secret))
    store = Struct.new(:data) { def load(_) = nil; def store(_, v) = (self.data = v); def delete(_) = nil }.new
    authorizer = Google::Auth::UserAuthorizer.new(client_id, DeliveryMethods::GmailApi::SCOPE, store, "http://localhost:1")

    # googleauth always adds access_type=offline and approval_prompt=force (consent screen + refresh
    # token); also passing prompt=consent makes Google reject the request ("Conflict params").
    url = authorizer.get_authorization_url(base_url: "http://localhost:1")
    puts <<~MSG

      1. Sign in as the SENDER account (#{config[:sender]}) and open:
         #{url}
      2. After approving, the browser is redirected to http://localhost:1/?code=...
         (the page won't load; that's expected). Copy the whole address, or just the `code` value.
    MSG
    print "Address or code: "
    input = $stdin.gets.to_s.strip
    query = input.include?("code=") ? input.split("?", 2).last : nil
    code = query ? URI.decode_www_form(query).to_h.fetch("code") : input
    credentials = authorizer.get_credentials_from_code(user_id: "sender", code: code, base_url: "http://localhost:1")

    puts <<~MSG

      Refresh token (put it in `bin/rails credentials:edit` under gmail.refresh_token):
      #{credentials.refresh_token}

      Reminder: the GCP project must be in "In production" publishing status, otherwise this
      token expires after 7 days.
    MSG
  end
end
