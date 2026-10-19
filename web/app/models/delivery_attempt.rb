class DeliveryAttempt < ApplicationRecord
  belongs_to :reminder_delivery

  enum :status, %w[accepted rejected received error].index_by(&:itself), validate: true
end
