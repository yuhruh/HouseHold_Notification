# A claim on (record, member, kind, channel, scheduled date): the unique index is the lock.
class ReminderLog < ApplicationRecord
  KINDS = %w[due_soon due_today overdue overdue_final next_due_soon next_due_today next_due_overdue next_due_final
             no_due_repeat snooze_ended].freeze

  belongs_to :record
  belongs_to :user
  belongs_to :reminder_delivery, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :channel, inclusion: { in: ReminderDelivery::CHANNELS }
end
