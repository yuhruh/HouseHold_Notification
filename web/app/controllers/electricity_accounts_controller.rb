# Ledger settings › Electricity (台電): bills from 台電's emails (ForwardedBillsPage)
class ElectricityAccountsController < ApplicationController
  include ForwardedBillsPage

  private

  def account_class = ElectricityAccount
  def default_category_name = "電費"
end
