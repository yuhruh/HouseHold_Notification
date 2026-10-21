# Dashboard (PRD §8): filters year, currency, type; mode paid date / billing period
class DashboardsController < ApplicationController
  include HouseholdScoped
  CYCLE_VIEWS = %w[timeline yoy].freeze

  def show
    authorize Record, :show?
    @query = DashboardQuery.new(Current.household, mode: params[:mode], year: params[:year].presence || Date.current.year,
      currency: params[:currency], record_type: params[:type].presence)
    @utility_query = @query.with(mode: params[:utility_mode].presence_in(DashboardQuery::MODES) || "period", record_type: nil)
    @charts = DashboardCharts.new(@query, utility_query: @utility_query)
    @counts = @query.unpaid_counts
    # Bills by billing cycle: one utility category (水費 first), as a timeline or year against year
    @cycle_category = @query.utility_categories.find { |c| c.id == params[:cycle_category].to_i } || @query.utility_categories.first
    @cycle_view = params[:cycle_view].presence_in(CYCLE_VIEWS) || CYCLE_VIEWS.first
  end
end
