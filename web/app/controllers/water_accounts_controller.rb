# Ledger settings › Water (台水): bills from 台水's emails (ForwardedBillsPage)
class WaterAccountsController < ApplicationController
  include ForwardedBillsPage

  private

  def account_class = WaterAccount
  def default_category_name = "水費"
end
