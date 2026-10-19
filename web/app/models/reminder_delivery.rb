# One digest message per member × household × channel × local day (PRD §6). Its status is the
# only status; reminder_logs point at it.
class ReminderDelivery < ApplicationRecord
  CHANNELS = %w[in_app email web_push].freeze

  belongs_to :household
  belongs_to :user
  belongs_to :resent_by, class_name: "User", optional: true
  has_many :reminder_logs, dependent: :nullify
  has_many :delivery_attempts, dependent: :delete_all
  has_one :notification, dependent: :nullify

  enum :channel, CHANNELS.index_by(&:itself), validate: true
  enum :status, %w[pending awaiting_receipt sent failed resolved].index_by(&:itself), validate: true

  # Records still in the digest, in a stable order
  def records = Record.where(id: reminder_logs.select(:record_id)).order(:due_on, :id)
end
