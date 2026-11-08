# frozen_string_literal: true

require "securerandom"

module NotifyKit
  module Services
    module Outbox
      # Claims due messages (with a lease) and processes each one:
      #
      #   1. recover: a message whose previous worker died mid-request has an attempt
      #      that started but never finished. Unless the provider de-duplicates, we
      #      cannot know whether the vendor got it => unknown_outcome, no resend.
      #   2. start_attempt is COMMITTED before the HTTP call (that is what makes 1. possible).
      #   3. deliver, then record the attempt and move the message to its next state.
      #      Every state change is fenced by worker_id, so a worker whose lease expired
      #      cannot overwrite the worker that took over.
      class Dispatch
        Outcome = Data.define(:message_id, :state, :lease_lost)

        def self.call(...) = new(...).call

        def initialize(storage:, providers:, retry_policy:, clock:, lease_seconds:, limit: 50, ids: nil)
          @storage = storage
          @providers = providers
          @retry_policy = retry_policy
          @clock = clock
          @lease_seconds = lease_seconds
          @limit = limit
          @ids = ids
          @worker_id = "#{Process.pid}-#{SecureRandom.hex(6)}"
        end

        def call
          claimed = @storage.claim(worker_id: @worker_id, now: @clock.call, lease_seconds: @lease_seconds,
                                   limit: @limit, ids: @ids)
          claimed.map { |stored| process(stored) }
        end

        private

        def process(stored)
          provider = @providers.fetch(stored.provider)
          return recover_in_flight(stored) if in_flight_without_idempotency?(stored, provider)

          attempt = @storage.start_attempt(message_id: stored.id, provider: stored.provider, now: @clock.call)
          context = DeliveryContext.new(message_id: stored.id, attempt_number: attempt.number)
          response = Messages::Deliver.call(message: stored.to_message, provider:, context:)
          accepted(stored, attempt, response)
        rescue DeliveryError => e
          failed(stored, attempt, provider, e)
        rescue ConfigurationError => e
          # e.g. the provider instance was removed from config: retrying cannot help.
          release(stored, States::FAILED, error: PermanentFailure.new(e.message))
        end

        def in_flight_without_idempotency?(stored, provider)
          return false unless (attempt = @storage.unfinished_attempt(stored.id))

          if provider.capabilities.idempotent_send
            @storage.finish_attempt(attempt.id, outcome: :unknown, now: @clock.call,
                                                error: UnknownOutcome.new("worker lost mid-request"))
            return false
          end
          true
        end

        def recover_in_flight(stored)
          attempt = @storage.unfinished_attempt(stored.id)
          error = UnknownOutcome.new("worker stopped during attempt ##{attempt.number}; vendor may have received it")
          @storage.finish_attempt(attempt.id, outcome: :unknown, now: @clock.call, error:)
          release(stored, States::UNKNOWN_OUTCOME, error:)
        end

        def accepted(stored, attempt, response)
          @storage.finish_attempt(attempt.id, outcome: :accepted, now: @clock.call,
                                              provider_message_id: response.provider_message_id)
          release(stored, States::ACCEPTED, provider_message_id: response.provider_message_id)
        end

        def failed(stored, attempt, provider, error)
          # validate! can raise before an attempt exists (message became invalid).
          number = attempt ? attempt.number : stored.attempts_count
          decision = @retry_policy.decide(error:, attempt_number: number,
                                          capabilities: provider.capabilities, now: @clock.call)
          if attempt
            @storage.finish_attempt(attempt.id, outcome: error.is_a?(UnknownOutcome) ? :unknown : :failed,
                                                now: @clock.call, error:)
          end

          case decision.action
          when :retry then release(stored, States::RETRY_SCHEDULED, error:, available_at: decision.at)
          when :unknown then release(stored, States::UNKNOWN_OUTCOME, error:)
          else release(stored, States::FAILED, error:)
          end
        end

        def release(stored, state, **attrs)
          ok = @storage.release(stored.id, worker_id: @worker_id, state:, now: @clock.call, **attrs)
          Outcome.new(message_id: stored.id, state:, lease_lost: !ok)
        end
      end
    end
  end
end
