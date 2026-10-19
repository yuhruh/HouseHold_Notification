# Joining by invitation is logged from now on; earlier accepted invitations get their entry once,
# dated when they were accepted.
class BackfillMemberJoinedEvents < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO security_events (user_id, actor_id, household_id, kind, metadata, created_at)
      SELECT memberships.user_id, memberships.user_id, invitations.household_id, 'member_joined',
             jsonb_build_object('role', invitations.role), invitations.accepted_at
      FROM invitations
      JOIN users ON users.email_address = invitations.email
      JOIN memberships ON memberships.user_id = users.id AND memberships.household_id = invitations.household_id
      WHERE invitations.accepted_at IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM security_events e WHERE e.kind = 'member_joined'
                        AND e.user_id = memberships.user_id AND e.household_id = invitations.household_id)
    SQL
  end

  def down
  end
end
