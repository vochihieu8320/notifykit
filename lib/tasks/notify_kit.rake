# frozen_string_literal: true

namespace :notify_kit do
  desc "Deliver due messages once (for cron / recurring jobs)"
  task dispatch_due: :environment do
    outcomes = NotifyKit.dispatch_due(limit: Integer(ENV.fetch("LIMIT", 100)))
    puts "notify_kit: processed #{outcomes.size} message(s)"
  end

  desc "Poll and deliver due messages until stopped (INTERVAL seconds between empty polls)"
  task work: :environment do
    interval = Float(ENV.fetch("INTERVAL", 1))
    limit = Integer(ENV.fetch("LIMIT", 50))
    running = true
    %w[INT TERM].each { |signal| trap(signal) { running = false } }

    while running
      processed = NotifyKit.dispatch_due(limit:).size
      sleep(interval) if processed.zero? && running
    end
  end
end
