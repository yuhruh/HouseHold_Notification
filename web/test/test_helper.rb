ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/omniauth_test_helper"
require_relative "test_helpers/reauth_test_helper"
require_relative "test_helpers/photo_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
    include PhotoTestHelper

    # rate_limit counters live in the controllers' memory store; start each test from zero
    setup { ActionController::Base.cache_store.clear }
  end
end
