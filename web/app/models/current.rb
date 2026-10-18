class Current < ActiveSupport::CurrentAttributes
  attribute :session, :household, :membership
  delegate :user, to: :session, allow_nil: true
end
