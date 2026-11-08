# frozen_string_literal: true

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "notify_kit"
require "notify_kit/rails"

module Dummy
  # Minimal host app used by integration specs.
  class Application < Rails::Application
    config.load_defaults 7.2
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.active_job.queue_adapter = :test
    config.active_record.maintain_test_schema = false
  end
end
