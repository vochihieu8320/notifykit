# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module NotifyKit
  module Generators
    # rails g notify_kit:install
    # Copies the migration and an initializer into the host app. Migrations are never
    # run automatically: the app owns its schema.
    class InstallGenerator < ::Rails::Generators::Base
      include ::ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)
      desc "Creates the NotifyKit migration and initializer"

      def create_migration_file
        migration_template "create_notify_kit_tables.rb.tt",
                           File.join(db_migrate_path, "create_notify_kit_tables.rb")
      end

      def create_initializer
        template "initializer.rb.tt", "config/initializers/notify_kit.rb"
      end
    end
  end
end
