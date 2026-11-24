module Supplies
  # What today's supplies digest says, for one household. Each alert goes once:
  #   low    — on the buy-by date, or down to "alert me when only N left" (ok → low)
  #   out    — on the run-out date (→ out), asking for a count
  #   expiry — once per batch, when some of it should still be left on its expiry date
  # An item that no longer needs buying goes back to ok, so its next run-out alerts again.
  # Returns the alert lines (empty when there's nothing to say); each line is worded in whatever
  # locale is current when #text is called, so every member reads it in their own language.
  class Alerts
    FORMATTER = Reminders::Wording::FORMATTER

    Line = Data.define(:supply, :kind, :left, :run_out_on, :buy_by, :last_purchase, :expires_on) do
      def text
        count = I18n.t("supplies.units.#{supply.unit}", count: left)
        case kind
        when :out then I18n.t("supplies.alerts.out", item: supply.name)
        when :expiry then I18n.t("supplies.alerts.expiry", item: supply.name, left: count, date: I18n.l(expires_on, format: :short))
        else
          main = if run_out_on
            I18n.t("supplies.alerts.low", item: supply.name, left: count, date: I18n.l(run_out_on, format: :short), buy_by: I18n.l(buy_by, format: :short))
          else
            I18n.t("supplies.alerts.at_level", item: supply.name, left: count)
          end
          return main unless last_purchase
          last = I18n.t("supplies.alerts.last_bought", store: last_purchase.store.presence || "—", quantity: last_purchase.quantity,
                        price: FORMATTER.money(last_purchase.total_price, last_purchase.currency))
          "#{main} #{last}"
        end
      end
    end

    def self.call(household, today: household.today) = new(household, today).call

    def initialize(household, today)
      @household = household
      @today = today
    end

    def call
      @household.supplies.active.includes(:category, :purchases, :counts).order(:name).flat_map do |supply|
        forecast = supply.forecast(today: @today)
        stock_lines(supply, forecast) + expiry_lines(supply, forecast)
      end
    end

    private

    def line(supply, kind, **details)
      Line.new(supply:, kind:, left: 0, run_out_on: nil, buy_by: nil, last_purchase: nil, expires_on: nil, **details)
    end

    def stock_lines(supply, forecast)
      if forecast.out? && forecast.enough_data?
        return [] if supply.alert_state == "out"
        supply.update!(alert_state: "out", alerted_at: Time.current)
        [ line(supply, :out) ]
      elsif forecast.buy_now?
        return [] unless supply.alert_state == "ok"
        supply.update!(alert_state: "low", alerted_at: Time.current)
        [ line(supply, :low, left: forecast.on_hand_rounded, run_out_on: forecast.run_out_on,
               buy_by: forecast.buy_by && [ forecast.buy_by, @today ].max, last_purchase: supply.latest_priced_purchase) ]
      else
        supply.update!(alert_state: "ok", alerted_at: nil) if supply.alert_state != "ok" && !forecast.needs_buying?
        []
      end
    end

    def expiry_lines(supply, forecast)
      expiring = forecast.expiring
      return [] if expiring.nil? || expiring.purchase.expiry_alerted_at

      expiring.purchase.update!(expiry_alerted_at: Time.current)
      [ line(supply, :expiry, left: expiring.left_at_expiry, expires_on: expiring.expires_on) ]
    end
  end
end
