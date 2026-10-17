module Spike
  # Called by the service worker after it shows a notification. Unauthenticated on purpose
  # (a service worker has no basic-auth credentials); the random single-use token is the proof.
  class PushReceiptsController < ApplicationController
    skip_forgery_protection

    def create
      push_send = PushSend.find_by!(receipt_token: params[:token], received_at: nil)
      push_send.update!(received_at: Time.current)
      head :no_content
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
  end
end
