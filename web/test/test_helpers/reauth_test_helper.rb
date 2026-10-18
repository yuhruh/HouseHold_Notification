module ReauthTestHelper
  def reauthenticate!(session_record = Current.session)
    session_record.update!(reauthenticated_at: Time.current)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ReauthTestHelper
end
