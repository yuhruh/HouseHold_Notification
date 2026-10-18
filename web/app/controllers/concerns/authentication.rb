module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    # Sessions last a year and slide: an active one is extended (at most daily) on use (PRD §10)
    def find_session_by_cookie
      return unless cookies.signed[:session_id]

      session_record = Session.active.find_by(id: cookies.signed[:session_id])
      if session_record&.refresh_due?
        session_record.refresh!
        write_session_cookie(session_record)
      end
      session_record
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session_record|
        Current.session = session_record
        write_session_cookie(session_record)
      end
    end

    def write_session_cookie(session_record)
      cookies.signed[:session_id] = { value: session_record.id, expires: session_record.expires_at, httponly: true, same_site: :lax }
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
