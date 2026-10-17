module Spike
  class PushSend < ApplicationRecord
    self.table_name = "spike_push_sends"

    belongs_to :subscription, class_name: "Spike::PushSubscription", foreign_key: :spike_push_subscription_id

    has_secure_token :receipt_token

    # Time from the push service accepting the message to the device confirming it.
    def latency
      received_at - sent_at if received_at && sent_at
    end
  end
end
