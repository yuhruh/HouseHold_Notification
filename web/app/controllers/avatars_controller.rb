# Avatars (PRD §7, §13): visible to the user and to members of households they share; 404 otherwise
class AvatarsController < ApplicationController
  include ActiveStorage::Streaming
  allow_unauthenticated_access only: :show

  def show
    raise ActiveRecord::RecordNotFound unless resume_session
    user = User.find(params[:user_id])
    shared = user == Current.user || Membership.where(user:, household_id: Current.user.memberships.select(:household_id)).exists?
    raise ActiveRecord::RecordNotFound unless shared && user.avatar.attached?

    response.headers["Cache-Control"] = "private, max-age=300"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_blob_stream user.avatar.blob, disposition: :inline
  end

  def update
    file = params.require(:avatar)
    raise Photos::Upload::Error, t("photos.errors.too_large", name: file.original_filename, max: 10) if file.size > Photos::Upload::MAX_BYTES
    raise Photos::Upload::Error, t("photos.errors.type", name: file.original_filename) unless Photos::Upload::TYPES.include?(Marcel::MimeType.for(file.tempfile, name: file.original_filename))

    clean = Photos::Sanitizer.call(file.tempfile.path, avatar: true)
    Current.user.avatar.attach(io: File.open(clean.path), filename: "avatar.jpg", content_type: "image/jpeg")
    redirect_to account_path, notice: t(".saved")
  rescue Photos::Upload::Error, ActionController::ParameterMissing => e
    redirect_to account_path, alert: e.message
  rescue Photos::Sanitizer::Invalid
    redirect_to account_path, alert: t("photos.errors.unreadable", name: file.original_filename)
  ensure
    clean&.close!
  end

  def destroy
    Current.user.avatar.purge_later
    redirect_to account_path, notice: t(".removed")
  end
end
