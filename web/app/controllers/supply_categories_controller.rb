# Settings › Categories › Supplies: the ledger's own supply categories. They are listed on the
# Categories page (categories#index); here they're added, renamed, archived (hidden from the item
# form, kept on the items in them) and, with no items, deleted. "Other" can only be renamed.
class SupplyCategoriesController < ApplicationController
  include HouseholdScoped
  before_action :set_category, only: %i[edit update archive destroy]

  def new
    authorize SupplyCategory
    @category = Current.household.supply_categories.new
  end

  def create
    authorize SupplyCategory
    @category = Current.household.supply_categories.new(category_params)
    @category.position = Current.household.supply_categories.maximum(:position).to_i + 1
    if @category.save
      redirect_to list_path, notice: t("categories.create.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @category
  end

  def update
    authorize @category
    if @category.update(category_params)
      redirect_to list_path, notice: t("categories.update.saved")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Toggles archived
  def archive
    authorize @category
    @category.update!(archived_at: @category.archived_at ? nil : Time.current)
    redirect_to list_path
  end

  def destroy
    authorize @category
    if @category.destroy
      redirect_to list_path, notice: t("categories.destroy.deleted")
    else
      redirect_to list_path, alert: t(".in_use")
    end
  end

  private

  def set_category
    @category = Current.household.supply_categories.find(params[:id])
  end

  def category_params = params.expect(supply_category: %i[name_zh name_en perishable])

  def list_path = household_categories_path(Current.household, anchor: "supplies")
end
