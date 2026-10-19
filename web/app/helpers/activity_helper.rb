# One line per household activity entry (PRD §14): who did what to whom, e.g.
# "Alex 將 Sam 改為檢視者". `users` is the batch-loaded id → User map; a deleted account reads
# "former member". Kinds without a sentence fall back to the plain event name.
module ActivityHelper
  SENTENCES = %w[member_joined role_changed member_removed member_left ownership_transferred household_updated records_deleted].freeze

  def activity_line(event, users)
    return t("security_events.#{event.kind}") unless SENTENCES.include?(event.kind)

    name = ->(id) { users[id]&.then { |u| u.display_name.presence || u.email_address } || t("household_settings.show.former_member") }
    role = event.metadata["role"].presence&.then { t("roles.#{_1}") } || "?"
    fields = Array(event.metadata["changes"]).map { Household.human_attribute_name(_1) }.to_sentence.presence || "—"
    t("household_settings.show.events.#{event.kind}", actor: name.(event.actor_id), member: name.(event.user_id), role:, fields:,
      count: event.metadata["count"].to_i)
  end
end
