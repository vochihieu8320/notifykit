# frozen_string_literal: true

module NotifyKit
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load File.expand_path("../../tasks/notify_kit.rake", __dir__)
    end
  end
end
