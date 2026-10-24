# Start of a bill's payment window (e.g. land value tax: payable Nov 1 – due Nov 30)
class AddPayableFromToRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :records, :payable_from, :date
  end
end
