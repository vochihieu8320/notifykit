# frozen_string_literal: true

module NotifyKit
  module Ports
    # Contract every storage adapter implements (Memory, ActiveRecord, ...).
    # The shared examples in spec/support/shared_examples/storage_adapter.rb are the
    # executable version of this contract.
    module Storage
      # Persist a new message, or return the existing one for the same
      # (namespace, idempotency_key). Must be atomic under concurrency.
      # Raises IdempotencyConflict when the key exists with a different fingerprint.
      # `on_commit` is called with the message id once the row is durably committed
      # (immediately for non-transactional stores) and only when a row was created.
      # @return [Array(StoredMessage, Boolean)] message and whether it was created
      def enqueue(message, available_at:, on_commit: nil)
        raise NotImplementedError
      end

      # Atomically take up to `limit` due messages for `worker_id` with a lease:
      # dispatchable messages with available_at <= now, plus `sending` messages whose
      # lease expired (their worker died). Two workers never receive the same message.
      # @return [Array<StoredMessage>] claimed messages, now in state `sending`
      def claim(worker_id:, now:, lease_seconds:, limit:, ids: nil)
        raise NotImplementedError
      end

      # @return [Attempt, nil] an attempt that started but never finished
      def unfinished_attempt(message_id)
        raise NotImplementedError
      end

      # Record (and commit) the start of a provider call BEFORE making it.
      # @return [Attempt]
      def start_attempt(message_id:, provider:, now:)
        raise NotImplementedError
      end

      def finish_attempt(attempt_id, outcome:, now:, error: nil, provider_message_id: nil)
        raise NotImplementedError
      end

      # Move a claimed message to its next state and drop the lease. Fenced by
      # worker_id: returns false (and changes nothing) if the lease was lost.
      def release(message_id, worker_id:, state:, now:, available_at: nil, error: nil, provider_message_id: nil)
        raise NotImplementedError
      end

      # @return [StoredMessage, nil]
      def find(message_id)
        raise NotImplementedError
      end

      # @return [Array<Attempt>] ordered by number
      def attempts(message_id)
        raise NotImplementedError
      end
    end
  end
end
