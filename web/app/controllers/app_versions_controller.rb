# The version an open app compares against its own (app-update controller), with what's new since
# the version it has. Never cached, so a deploy shows up on the next check.
class AppVersionsController < ApplicationController
  allow_unauthenticated_access

  def show
    response.headers["Cache-Control"] = "no-store"
    notes = AppVersion.since(params[:since]).map { |e| { version: e.version, date: I18n.l(e.date, format: :long), notes: e.notes } }
    render json: { version: AppVersion.current, build: AppVersion.build, notes: }
  end
end
