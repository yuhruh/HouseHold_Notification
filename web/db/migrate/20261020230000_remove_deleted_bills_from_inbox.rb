# Deleting a bill takes it out of the inbox from now on (Reminders::Inbox.forget!). Bills deleted
# before that left their digests behind; a deleted bill's reminder logs went with it, so a digest
# with fewer logs than lines lost bills: it is rewritten from the logs left, or removed if none are.
class RemoveDeletedBillsFromInbox < ActiveRecord::Migration[8.1]
  def up
    Notification.where(kind: "reminder_digest").where.not(reminder_delivery_id: nil).includes(:reminder_delivery).find_each do |note|
      delivery = note.reminder_delivery
      logs = delivery.reminder_logs.includes(:record).order(:id).to_a
      next if logs.size >= note.body.to_s.lines.size

      logs.empty? ? note.destroy! : note.update!(Reminders::Inbox.contents(delivery, logs, delivery.run_on))
    end
  end

  def down
  end
end
