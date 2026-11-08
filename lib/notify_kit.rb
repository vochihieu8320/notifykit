# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
# errors.rb defines the whole error taxonomy (many constants) => loaded eagerly below.
loader.ignore("#{__dir__}/notify_kit/errors.rb")
# Rails/ActiveRecord glue is loaded explicitly (see notify_kit/rails.rb) so that
# `require "notify_kit"` never pulls in Rails.
loader.ignore("#{__dir__}/notify_kit/rails.rb")
loader.ignore("#{__dir__}/notify_kit/rails")
loader.ignore("#{__dir__}/generators")
loader.ignore("#{__dir__}/tasks")
loader.setup

require_relative "notify_kit/errors"

# NotifyKit: reliable notifications on your own infrastructure.
#
#   NotifyKit.configure do |c|
#     c.provider :shop_zalo, :zalo_zns, app_id: "...", app_secret: "...", token_store: ...
#     c.default_provider = :shop_zalo
#   end
#
#   NotifyKit.deliver(to: "0987654321", template: "order_paid", data: { order_code: "A1" },
#                     idempotency_key: "order:1:paid")
module NotifyKit
  class << self
    def configure
      yield configuration
      @client = nil
      configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def client
      @client ||= Client.new(configuration)
    end

    def reset!
      @configuration = nil
      @client = nil
    end

    def deliver(**) = client.deliver(**)
    def status(message_id) = client.status(message_id)
    def attempts(message_id) = client.attempts(message_id)
    def dispatch_due(**) = client.dispatch_due(**)
  end
end

require "notify_kit/rails" if defined?(Rails::Railtie)
