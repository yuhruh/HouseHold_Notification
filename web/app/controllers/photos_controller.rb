# Record photos (PRD §7), served only to household members. Signed-out or non-member requests get
# 404, never a sign-in redirect that would reveal the photo exists.
class PhotosController < ApplicationController
  include ActiveStorage::Streaming
  include HouseholdScoped
  allow_unauthenticated_access only: :show
  skip_before_action :set_household, only: :show
  before_action :member_or_not_found, only: :show
  before_action :set_record

  VARIANTS = { "thumb" => { resize_to_limit: [ 400, 400 ] } }.freeze

  def show
    authorize @record, :show?
    photo = @record.photos.find(params[:id])
    blob = params[:variant] ? photo.variant(VARIANTS.fetch(params[:variant]) { raise ActiveRecord::RecordNotFound }).processed.image.blob : photo.blob
    response.headers["Cache-Control"] = "private, max-age=300"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_blob_stream blob, disposition: :inline
  end

  def create
    authorize @record, :update?
    result = Photos::Upload.attach(@record, params[:photos])
    notice = [ (t(".added", count: result.added) if result.added.positive?), (t(".skipped", count: result.skipped) if result.skipped.positive?) ]
    redirect_to household_record_path(Current.household, @record), notice: notice.compact.join(" ")
  rescue Photos::Upload::Error => e
    redirect_to household_record_path(Current.household, @record), alert: e.message
  end

  def destroy
    authorize @record, :update?
    @record.photos.find(params[:id]).purge_later
    redirect_to household_record_path(Current.household, @record), notice: t(".removed")
  end

  private

  def member_or_not_found
    raise ActiveRecord::RecordNotFound unless resume_session
    set_household
  end

  def set_record
    @record = Current.household.records.find(params[:record_id])
  end
end
