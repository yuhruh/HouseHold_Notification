# Recurring bills get their next one from the template: a next due date left on a linked record
# (typically the maintenance record a template was made from) would list the task twice in To Pay
# and offer a Done that creates an unlinked duplicate. Record now clears it on save; this clears
# the ones already stored.
class ClearNextDueOnRecurringRecords < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE records SET next_due_on = NULL WHERE recurring_template_id IS NOT NULL AND next_due_on IS NOT NULL"
  end

  def down
    # Nothing to restore: the template's schedule replaced these dates
  end
end
