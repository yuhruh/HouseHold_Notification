# Categories (PRD §3): bilingual names, archive instead of delete once used, and the item-name
# aliases imports saved. detail_required isn't editable in v1.
class CategoriesController < ApplicationController
  include HouseholdScoped
  before_action :set_category, only: %i[edit update archive destroy]

  def index
    authorize Category
    @categories = Current.household.categories.ordered.includes(:category_aliases)
    @counts = Current.household.records.group(:category_id).count
  end

  def new
    authorize Category
    @category = Current.household.categories.new(record_type: params[:record_type].presence_in(Category::RECORD_TYPES.values) || "expense")
  end

  def create
    authorize Category
    @category = Current.household.categories.new(params.expect(category: %i[record_type name_zh name_en]))
    @category.position = Current.household.categories.where(record_type: @category.record_type).maximum(:position).to_i + 1
    if @category.save
      redirect_to household_categories_path(Current.household), notice: t(".created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @category
  end

  # Renaming keeps the records; titles that still equal the old name follow the new one, and the
  # old name becomes an alias
  def update
    authorize @category
    old_name = @category.name_zh
    Category.transaction do
      @category.update!(params.expect(category: %i[name_zh name_en]))
      if @category.saved_change_to_name_zh?
        @category.records.where(title: old_name).find_each { |record| record.update!(title: @category.name_zh) }
        # The sheet still says the old name: keep mapping it here on the next import
        Current.household.category_aliases.find_or_initialize_by(alias: old_name).update!(category: @category)
      end
    end
    redirect_to household_categories_path(Current.household), notice: t(".saved")
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  # Toggles archived: hidden from the record form, kept on existing records
  def archive
    authorize @category
    @category.update!(archived_at: @category.archived_at ? nil : Time.current)
    redirect_to household_categories_path(Current.household)
  end

  def destroy
    authorize @category
    if @category.destroy
      redirect_to household_categories_path(Current.household), notice: t(".deleted")
    else
      redirect_to household_categories_path(Current.household), alert: t(".in_use")
    end
  end

  def destroy_alias
    authorize Category
    Current.household.category_aliases.find(params[:alias_id]).destroy!
    redirect_to household_categories_path(Current.household), notice: t(".alias_removed")
  end

  private

  def set_category
    @category = Current.household.categories.find(params[:id])
  end
end
