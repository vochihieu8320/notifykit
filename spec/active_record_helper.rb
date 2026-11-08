# frozen_string_literal: true

# Loads the dummy Rails app on a real database (Postgres in docker-compose).
# Require from integration specs only: `require "active_record_helper"`.
ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"

module ActiveRecordHelper
  TABLES = %w[notify_kit_delivery_attempts notify_kit_messages notify_kit_provider_tokens orders].freeze

  def self.prepare_schema!
    ActiveRecord::Migration.verbose = false
    connection = ActiveRecord::Base.connection
    (connection.tables - ["ar_internal_metadata"]).each { |t| connection.drop_table(t, force: :cascade) }
    ActiveRecord::Migrator.migrations_paths = Rails.application.paths["db/migrate"].to_a
    ActiveRecord::Base.connection_pool.migration_context.migrate
  end

  def self.truncate!
    ActiveRecord::Base.connection.execute("TRUNCATE #{TABLES.join(', ')} RESTART IDENTITY CASCADE")
  end

  # Run `count` threads, each with its own DB connection, released afterwards.
  def in_threads(count, &block)
    Array.new(count) do |i|
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { block.call(i) } }
    end.map(&:value)
  end
end

ActiveRecordHelper.prepare_schema!

RSpec.configure do |config|
  config.include ActiveRecordHelper, :db
  config.before(:each, :db) do
    ActiveRecordHelper.truncate!
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end
end
