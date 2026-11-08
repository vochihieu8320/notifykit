# frozen_string_literal: true

module NotifyKit
  module Storage
    # Thread-safe, process-local storage. Default adapter: zero setup, best-effort
    # (nothing survives a restart). Also the reference implementation of the
    # Storage port, verified by the same shared examples as ActiveRecord.
    class Memory
      include Ports::Storage

      def initialize
        @messages = {}
        @attempts = Hash.new { |h, k| h[k] = [] }
        @keys = {}
        @sequence = 0
        @mutex = Mutex.new
      end

      def enqueue(message, available_at:, on_commit: nil)
        stored, created = @mutex.synchronize { insert_or_find(message, available_at) }
        on_commit&.call(stored.id) if created
        [stored, created]
      end

      def claim(worker_id:, now:, lease_seconds:, limit:, ids: nil)
        @mutex.synchronize do
          due = @messages.values.select { |m| claimable?(m, now) && (ids.nil? || ids.include?(m.id)) }
          due.min_by(limit, &:available_at).map do |m|
            update(m.id, state: States::SENDING, locked_by: worker_id, locked_until: now + lease_seconds)
          end
        end
      end

      def unfinished_attempt(message_id)
        @mutex.synchronize { @attempts[message_id].find(&:in_flight?) }
      end

      def start_attempt(message_id:, provider:, now:)
        @mutex.synchronize do
          number = @messages.fetch(message_id).attempts_count + 1
          update(message_id, attempts_count: number)
          attempt = Attempt.new(id: next_id, message_id:, number:, provider: provider.to_s, outcome: nil,
                                error_category: nil, error_message: nil, provider_message_id: nil,
                                started_at: now, finished_at: nil)
          @attempts[message_id] << attempt
          attempt
        end
      end

      def finish_attempt(attempt_id, outcome:, now:, error: nil, provider_message_id: nil)
        @mutex.synchronize do
          list = @attempts.values.find { |as| as.any? { |a| a.id == attempt_id } }
          index = list.index { |a| a.id == attempt_id }
          list[index] = list[index].with(outcome: outcome.to_s, finished_at: now, provider_message_id:,
                                         error_category: error&.category&.to_s, error_message: error&.message)
        end
      end

      def release(message_id, worker_id:, state:, now:, available_at: nil, error: nil, provider_message_id: nil)
        @mutex.synchronize do
          current = @messages[message_id]
          return false unless current && current.locked_by == worker_id

          attrs = { state:, locked_by: nil, locked_until: nil, updated_at: now,
                    last_error_category: error&.category&.to_s, last_error_message: error&.message }
          attrs[:available_at] = available_at if available_at
          attrs[:provider_message_id] = provider_message_id if provider_message_id
          update(message_id, **attrs)
          true
        end
      end

      def find(message_id) = @mutex.synchronize { @messages[message_id] }
      def attempts(message_id) = @mutex.synchronize { @attempts[message_id].sort_by(&:number) }

      private

      def insert_or_find(message, available_at)
        key = message.idempotency_key && [message.namespace, message.idempotency_key]
        if key && (existing_id = @keys[key])
          existing = @messages.fetch(existing_id)
          if existing.fingerprint != message.fingerprint
            raise IdempotencyConflict.new("idempotency key #{message.idempotency_key.inspect} reused with a " \
                                          "different payload", message_id: existing.id)
          end

          return [existing, false]
        end

        stored = build(message, available_at)
        @messages[stored.id] = stored
        @keys[key] = stored.id if key
        [stored, true]
      end

      def build(message, now)
        StoredMessage.new(
          id: next_id, namespace: message.namespace, idempotency_key: message.idempotency_key,
          fingerprint: message.fingerprint, provider: message.provider, to: message.to,
          template: message.template, data: message.data, content: message.content,
          state: States::QUEUED, attempts_count: 0, available_at: now, locked_by: nil, locked_until: nil,
          provider_message_id: nil, last_error_category: nil, last_error_message: nil,
          created_at: now, updated_at: now
        )
      end

      def claimable?(message, now)
        (States::DISPATCHABLE.include?(message.state) && message.available_at <= now) ||
          (message.state == States::SENDING && message.locked_until && message.locked_until <= now)
      end

      def update(id, **attrs)
        @messages[id] = @messages.fetch(id).with(**attrs)
      end

      def next_id = (@sequence += 1)
    end
  end
end
