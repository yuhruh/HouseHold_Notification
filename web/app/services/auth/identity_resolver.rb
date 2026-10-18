module Auth
  # Who a Google sign-in belongs to (PRD §10). Rules, in order:
  # 1. a known (provider, uid) signs in to its user;
  # 2. a signed-in user connecting Google links it to themselves;
  # 3. otherwise the Google email must be verified, and if it matches a verified email_address the
  #    identity is linked to that user;
  # 4. else a new user is created with that (now verified) address.
  # An address held only as someone's unconfirmed_email doesn't count: that sign-up can never confirm it now.
  class IdentityResolver
    Result = Data.define(:status, :user)

    def initialize(auth, current_user:, time_zone:)
      @auth = auth
      @current_user = current_user
      @time_zone = time_zone
    end

    def call
      if identity = Identity.find_by(provider: @auth.provider, uid: @auth.uid)
        return Result.new(:conflict, @current_user) if @current_user && identity.user != @current_user

        identity.update!(email:, raw_info:)
        return Result.new(:signed_in, identity.user)
      end

      if @current_user
        return Result.new(:conflict, @current_user) if @current_user.identities.exists?(provider: @auth.provider)

        link(@current_user)
        return Result.new(:linked, @current_user)
      end

      return Result.new(:unverified_email, nil) unless email_verified? && email.present?

      if user = User.find_by(email_address: email)
        link(user)
        return Result.new(:signed_in, user)
      end

      user = User.transaction do
        User.create!(email_address: email, email_confirmed_at: Time.current, display_name: @auth.info.name,
          time_zone: User.valid_time_zone(@time_zone)).tap { |u| link(u) }
      end
      Result.new(:created, user)
    rescue ActiveRecord::RecordNotUnique
      Result.new(:conflict, @current_user)
    end

    private
      def email = @auth.info.email.to_s.strip.downcase.presence

      # Google sends a boolean; some libraries pass it through as a string
      def email_verified? = [ true, "true" ].include?(@auth.extra&.raw_info&.email_verified)

      def raw_info = @auth.info.to_h.slice("name", "email", "image")

      def link(user)
        user.identities.create!(provider: @auth.provider, uid: @auth.uid, email:, raw_info:)
      end
  end
end
