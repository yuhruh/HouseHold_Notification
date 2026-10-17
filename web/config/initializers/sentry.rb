# Error alerts (PRD: Monitoring & alerts). Enabled only when a DSN is configured,
# so development and test never report.
dsn = ENV["SENTRY_DSN"].presence || Rails.application.credentials.dig(:sentry, :dsn)

if dsn
  Sentry.init do |config|
    config.dsn = dsn
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
    config.send_default_pii = false
    config.traces_sample_rate = 0.0
  end
end
