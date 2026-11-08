# frozen_string_literal: true

require "active_record_helper"
require "generators/notify_kit/install/install_generator"
require "tmpdir"

RSpec.describe NotifyKit::Generators::InstallGenerator do
  it "creates the migration and the initializer" do
    Dir.mktmpdir do |dir|
      described_class.start([], destination_root: dir, quiet: true)
      migration = Dir[File.join(dir, "db/migrate/*_create_notify_kit_tables.rb")].first
      aggregate_failures do
        unique_key = "add_index :notify_kit_messages, %i[namespace idempotency_key], unique: true"
        expect(File.read(migration)).to include(unique_key)
        expect(File.read(File.join(dir, "config/initializers/notify_kit.rb"))).to include("ActiveRecordStorage")
      end
    end
  end
end
