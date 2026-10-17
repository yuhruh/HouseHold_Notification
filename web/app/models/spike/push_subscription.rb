module Spike
  class PushSubscription < ApplicationRecord
    self.table_name = "spike_push_subscriptions"

    has_many :sends, class_name: "Spike::PushSend", foreign_key: :spike_push_subscription_id, dependent: :delete_all

    validates :endpoint, :p256dh, :auth, presence: true
  end
end
