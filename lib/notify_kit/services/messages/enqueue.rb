# frozen_string_literal: true

module NotifyKit
  module Services
    module Messages
      # Accepts a delivery request: validates it against the provider (no network),
      # then persists it idempotently. With ActiveRecord storage this runs inside the
      # caller's transaction, so the message commits or rolls back with the business
      # data: that row IS the transactional outbox entry.
      class Enqueue
        def self.call(...) = new(...).call

        def initialize(message:, providers:, storage:, on_commit:, now:)
          @message = message
          @providers = providers
          @storage = storage
          @on_commit = on_commit
          @now = now
        end

        def call
          provider = @providers.fetch(@message.provider)
          provider.validate!(@message)
          stored, created = @storage.enqueue(@message, available_at: @now, on_commit: @on_commit)
          Result.success(message_id: stored.id, state: stored.state, duplicate: !created)
        rescue IdempotencyConflict, DeliveryError => e
          Result.failure(e, message_id: e.respond_to?(:message_id) ? e.message_id : nil)
        end
      end
    end
  end
end
