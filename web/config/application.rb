require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Web
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # Each request runs in the user's zone (Localization); storage stays UTC (PRD §11)
    config.i18n.available_locales = [ :"zh-TW", :en ]
    config.i18n.default_locale = :"zh-TW"
    config.i18n.fallbacks = [ :en ]

    # Encrypts Google Drive refresh tokens (DriveBackup); production keys are Railway variables
    config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

    # Photos are private (PRD §7): no public-by-link /rails/active_storage routes; PhotosController
    # and AvatarsController serve files after the household check.
    config.active_storage.draw_routes = false
    config.active_storage.variant_processor = :vips
    # Records use optimistic locking: a photo's upload and its background analysis must not touch the
    # record, or each touch bumps lock_version (concurrent analyze jobs then hit StaleObjectError,
    # and an open edit form reads as changed elsewhere)
    config.active_storage.touch_attachment_records = false
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
