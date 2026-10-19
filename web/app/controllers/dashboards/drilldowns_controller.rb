# The raw records behind a clicked chart element, from the same DashboardQuery (PRD §8), so the
# total always equals the clicked value
class Dashboards::DrilldownsController < ApplicationController
  include HouseholdScoped

  def show
    authorize Record, :show?
    @query = DashboardQuery.new(Current.household, mode: params[:mode], year: params[:year], currency: params[:currency],
      record_type: params[:record_type].presence)
    filters = params.permit(:month, :category_id, :payment_method_id).to_h.symbolize_keys.compact_blank
    @month = filters[:month]
    @box = params[:box].present?
    @rows = @query.drilldown(**filters)
    @group = @box ? @query.box_groups.find { |g| g[:category].id == filters[:category_id].to_i } : nil
    @total = @rows.sum { |_, amount| amount }
  end
end
