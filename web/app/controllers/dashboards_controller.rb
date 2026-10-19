# Dashboard (PRD §8): filters year, currency, type; mode paid date / billing period
class DashboardsController < ApplicationController
  include HouseholdScoped

  def show
    authorize Record, :show?
    @query = DashboardQuery.new(Current.household, mode: params[:mode], year: params[:year].presence || Date.current.year,
      currency: params[:currency], record_type: params[:type].presence)
    @utility_query = @query.with(mode: params[:utility_mode].presence_in(DashboardQuery::MODES) || "period", record_type: nil)
    @charts = DashboardCharts.new(@query, utility_query: @utility_query)
    @counts = @query.unpaid_counts
  end
end
