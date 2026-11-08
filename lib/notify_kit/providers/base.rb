# frozen_string_literal: true

module NotifyKit
  module Providers
    # Every provider type subclasses Base. A provider:
    #   - declares capabilities (what it can do),
    #   - validates a message WITHOUT network I/O,
    #   - delivers it, returning a ProviderResponse or raising exactly one
    #     NotifyKit::DeliveryError subclass. Never raw HTTP/JSON exceptions.
    # Providers never touch storage; retries and state are the services' job.
    class Base
      attr_reader :name

      # @param name [Symbol] provider *instance* name from the configuration
      # @param transport [#post] HTTP transport (injected so specs can swap it)
      # @param clock [#call] returns current Time
      def initialize(name:, transport: nil, clock: -> { Time.now.utc }, **_options)
        @name = name.to_sym
        @transport = transport
        @clock = clock
      end

      # @return [NotifyKit::Capabilities]
      def capabilities
        raise NotImplementedError, "#{self.class} must declare capabilities"
      end

      # Raise InvalidRecipient / InvalidTemplate / NotEligible for messages that can
      # never succeed. Called before persisting and again before each attempt.
      def validate!(_message) = nil

      # @param message [NotifyKit::Message]
      # @param context [NotifyKit::DeliveryContext]
      # @return [NotifyKit::ProviderResponse]
      def deliver(_message, _context)
        raise NotImplementedError, "#{self.class} must implement #deliver"
      end

      private

      attr_reader :transport, :clock
    end
  end
end
