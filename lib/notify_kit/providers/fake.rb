# frozen_string_literal: true

module NotifyKit
  module Providers
    # Deterministic in-memory provider for specs (ours and the host app's).
    #
    #   c.provider :test, :fake, outcomes: [NotifyKit::RateLimited.new(retry_after: 5), :ok]
    #
    # Each delivery consumes the next outcome (default :ok). `received` records every
    # message that "reached the vendor": accepted ones and UnknownOutcome ones, since
    # an unknown outcome means the vendor may have got it. That makes physical
    # duplicates observable in specs.
    class Fake < Base
      attr_reader :received

      def initialize(outcomes: [], idempotent_send: false, invalid_recipients: [], **)
        super(**)
        @outcomes = outcomes.dup
        @idempotent_send = idempotent_send
        @invalid_recipients = invalid_recipients
        @received = []
        @attempts = 0
        @mutex = Mutex.new
      end

      def capabilities
        Capabilities.new(channel: :test, recipient_kind: :any, idempotent_send: @idempotent_send, tracking_id: true)
      end

      def validate!(message)
        raise InvalidRecipient, "fake: #{message.to} is rejected" if @invalid_recipients.include?(message.to)
      end

      def deliver(message, context)
        outcome = @mutex.synchronize do
          @attempts += 1
          @outcomes.shift || :ok
        end

        return accept(message, context) if outcome == :ok

        error = outcome.is_a?(Class) ? outcome.new("fake #{outcome.name}") : outcome
        record(message, context) if error.is_a?(UnknownOutcome)
        raise error
      end

      def attempts = @mutex.synchronize { @attempts }

      private

      def accept(message, context)
        record(message, context)
        ProviderResponse.new(provider_message_id: "fake-#{context.message_id}-#{context.attempt_number}")
      end

      def record(message, context)
        @mutex.synchronize { @received << { message: message, context: context } }
      end
    end
  end
end
