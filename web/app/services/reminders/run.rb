module Reminders
  # One hourly reminder run (PRD §6). For each member whose local hour ≥ their reminder hour:
  # gather the latest due stage of every record, claim a reminder_logs row per item and channel
  # (the unique index is the lock), and only when something was claimed create that channel's
  # digest delivery. One digest per member × household × channel × local day, plus at most one
  # same-day addition for bills due today or earlier that never reminded this member.
  class Run
    Item = Data.define(:record, :kind, :scheduled_on, :snoozed)
    STUCK_AFTER = 2.hours

    def self.call(now: Time.current) = new(now).call

    def initialize(now)
      @now = now
    end

    def call
      recover_stuck_deliveries
      Household.includes(memberships: :user).find_each do |household|
        household.memberships.each { |membership| process(household, membership) }
      end
    end

    private

    # Claimed but never dispatched (the run died in between): dispatch on the next run
    def recover_stuck_deliveries
      ReminderDelivery.pending.where(channel: %w[email web_push], dispatched_at: nil).where(created_at: ...(@now - STUCK_AFTER))
        .find_each { |delivery| DeliverReminderJob.perform_later(delivery.id) }
    end

    def process(household, membership)
      user = membership.user
      Time.use_zone(user.time_zone) do
        local = @now.in_time_zone
        next if local.hour < user.reminder_hour

        today = local.to_date
        items = items_for(household, user, today)
        next if items.empty?

        # "Never reminded this member" is judged before any channel claims (same-day addition rule)
        reminded = ReminderLog.where(user:, record_id: items.map { |i| i.record.id }).distinct.pluck(:record_id).to_set
        channels(membership).each { |channel| deliver(household, user, channel, items, today, reminded) }
        ReminderSnooze.where(user:, record_id: items.map { |i| i.record.id }).where(until_on: ..today).delete_all
      end
    end

    def channels(membership)
      pref = NotificationPreference.for(membership)
      list = [ "in_app" ]
      list << "email" if pref.email && membership.user.email_address.present?
      list << "web_push" if pref.web_push
      list
    end

    def items_for(household, user, today)
      lead = household.reminder_lead_days
      snoozes = ReminderSnooze.where(user:).joins(:record).where(records: { household_id: household.id }).pluck(:record_id, :until_on).to_h
      records = household.records.where("(settled = false AND (due_on IS NOT NULL OR reminder_frequency <> 'none')) OR next_due_on IS NOT NULL")
      chain_bills = household.records.where(settled: false).where.not(due_on: nil).pluck(:category_id, :details, :due_on)

      records.flat_map do |record|
        stages = [ Schedule.current_stage(record, today, lead_days: lead) ]
        stages << Schedule.next_due_stage(record, today, lead_days: lead) unless covered_by_bill?(record, chain_bills)
        stages.compact!
        snoozed_until = snoozes[record.id]
        if snoozed_until && today < snoozed_until
          stages.map { |kind, date| Item.new(record, kind, date, true) }
        elsif snoozed_until && stages.empty?
          [ Item.new(record, "snooze_ended", snoozed_until, false) ]
        else
          stages.map { |kind, date| Item.new(record, kind, date, false) }
        end
      end
    end

    # A next-due reminder is silent while an unpaid bill of the same chain is due within ±30 days
    def covered_by_bill?(record, chain_bills)
      return false unless record.next_due_on
      key = chain_key(record.details)
      chain_bills.any? do |category_id, details, due_on|
        category_id == record.category_id && chain_key(details) == key && (due_on - record.next_due_on).abs <= 30
      end
    end

    def chain_key(details) = details.to_s.unicode_normalize(:nfkc).split(/[、,，\/;；]+/).map(&:strip).reject(&:empty?).sort.join("、")

    def deliver(household, user, channel, items, today, reminded)
      addition = ReminderDelivery.exists?(household:, user:, channel:, run_on: today, addition: false)
      if addition
        return if ReminderDelivery.exists?(household:, user:, channel:, run_on: today, addition: true)
        items = items.select do |item|
          !item.snoozed && item.record.due_on && item.record.due_on <= today && !reminded.include?(item.record.id)
        end
      end
      return if items.empty?

      ReminderDelivery.transaction do
        claimed = items.filter_map { |item| claim(item, user, channel) }
        sendable = claimed.reject(&:snoozed)
        next if sendable.empty?

        delivery = ReminderDelivery.create!(household:, user:, channel:, run_on: today, addition:,
          status: channel == "in_app" ? "sent" : "pending", sent_at: (@now if channel == "in_app"))
        ReminderLog.where(id: sendable.map(&:id)).update_all(reminder_delivery_id: delivery.id)
        if channel == "in_app"
          Inbox.digest!(delivery, today)
        else
          DeliverReminderJob.perform_later(delivery.id)
        end
      end
    rescue ActiveRecord::RecordNotUnique
      nil # a concurrent run created today's delivery; its claims won
    end

    def claim(item, user, channel)
      ReminderLog.transaction(requires_new: true) do
        ReminderLog.create!(record: item.record, user:, kind: item.kind, channel:, scheduled_on: item.scheduled_on, snoozed: item.snoozed)
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
