# frozen_string_literal: true

# ActiveRecord / ActiveJob / Rails integration. Loaded automatically when Rails is
# present at `require "notify_kit"`; otherwise `require "notify_kit/rails"` yourself
# after ActiveRecord is loaded.
require "active_record"
require "active_job"
require "notify_kit"

require_relative "rails/records/application_record"
require_relative "rails/records/concerns/idempotent"
require_relative "rails/records/concerns/leasable"
require_relative "rails/records/concerns/state_machine"
require_relative "rails/records/message"
require_relative "rails/records/delivery_attempt"
require_relative "rails/records/provider_token"
require_relative "rails/active_record_storage"
require_relative "rails/active_record_token_store"
require_relative "rails/dispatch_job"
require_relative "rails/active_job_dispatcher"
require_relative "rails/railtie" if defined?(Rails::Railtie)
