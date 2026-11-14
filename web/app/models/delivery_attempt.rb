# One device or email try for a reminder digest, or a push for a notification ("bill paid")
class DeliveryAttempt < ApplicationRecord
  belongs_to :reminder_delivery, optional: true
  belongs_to :notification, optional: true

  enum :status, %w[accepted rejected received error].index_by(&:itself), validate: true
end
