# frozen_string_literal: true

module NotifyKit
  module Storage
    # Durable storage on the host app's own database through ActiveRecord.
    # Works with any adapter ActiveRecord supports; SKIP LOCKED is used where available.
    #
    # Guarantees:
    #   - at most one logical message per (namespace, idempotency_key)  [unique index]
    #   - a message is persisted iff the caller's transaction commits    [transactional outbox]
    #   - each due message is processed by one worker at a time          [SKIP LOCKED + lease]
    #   - a crashed worker's message is recovered after its lease expires
    class ActiveRecordStorage
      include Ports::Storage

      ERROR_MESSAGE_LIMIT = 1_000

      def enqueue(message, available_at:, on_commit: nil)
        record, created = Records::Message.insert_idempotently!(attributes_for(message, available_at))
        schedule(record, on_commit) if created && on_commit
        [record.to_stored, created]
      end

      def claim(worker_id:, now:, lease_seconds:, limit:, ids: nil)
        Records::Message.claim!(worker_id:, now:, lease_seconds:, limit:, ids:).map(&:to_stored)
      end

      def unfinished_attempt(message_id)
        Records::DeliveryAttempt.in_flight.where(message_id:).order(:number).last&.to_attempt
      end

      def start_attempt(message_id:, provider:, now:)
        Records::Message.transaction do
          message = Records::Message.find(message_id)
          number = message.attempts_count + 1
          message.update_columns(attempts_count: number, updated_at: now)
          Records::DeliveryAttempt.create!(message_id:, number:, provider: provider.to_s, started_at: now).to_attempt
        end
      end

      def finish_attempt(attempt_id, outcome:, now:, error: nil, provider_message_id: nil)
        Records::DeliveryAttempt.where(id: attempt_id).update_all(
          outcome: outcome.to_s, finished_at: now, provider_message_id:,
          error_category: error&.category&.to_s, error_message: truncate(error&.message), updated_at: now
        )
      end

      def release(message_id, worker_id:, state:, now:, available_at: nil, error: nil, provider_message_id: nil)
        unless Records::Message.transition_allowed?(States::SENDING, state)
          raise ArgumentError, "illegal transition sending -> #{state}"
        end

        attrs = { state:, updated_at: now, last_error_category: error&.category&.to_s,
                  last_error_message: truncate(error&.message) }
        attrs[:available_at] = available_at if available_at
        attrs[:provider_message_id] = provider_message_id if provider_message_id
        Records::Message.release!(message_id, worker_id:, attrs:)
      end

      def find(message_id) = Records::Message.find_by(id: message_id)&.to_stored

      def attempts(message_id)
        Records::DeliveryAttempt.where(message_id:).order(:number).map(&:to_attempt)
      end

      private

      def attributes_for(message, available_at)
        { namespace: message.namespace, idempotency_key: message.idempotency_key,
          payload_fingerprint: message.fingerprint, provider: message.provider.to_s, recipient: message.to,
          template: message.template, data: message.data, content: message.content,
          state: States::QUEUED, available_at: }
      end

      # Inside a transaction: wait for the real commit (and never fire on rollback).
      # Outside one: the row is already committed.
      def schedule(record, on_commit)
        if Records::Message.connection.transaction_open?
          record.on_commit { on_commit.call(record.id) }
        else
          on_commit.call(record.id)
        end
      end

      def truncate(text) = text&.slice(0, ERROR_MESSAGE_LIMIT)
    end
  end
end
