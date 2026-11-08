# frozen_string_literal: true

module NotifyKit
  # Decides what happens after a failed attempt, from the error CLASS and the
  # provider's capabilities only (never vendor codes):
  #
  #   RateLimited, TransientFailure  -> retry with backoff (honour Retry-After)
  #   UnknownOutcome                 -> retry only if provider.idempotent_send,
  #                                     otherwise stop in `unknown_outcome`
  #   everything else                -> fail (retrying cannot help)
  #   attempts exhausted             -> fail
  class RetryPolicy
    Decision = Data.define(:action, :at) do
      def retry? = action == :retry
    end

    RETRYABLE = [RateLimited, TransientFailure].freeze

    attr_reader :max_attempts

    def initialize(max_attempts: 5, base_delay: 2.0, max_delay: 300.0, random: Random.new)
      @max_attempts = max_attempts
      @base_delay = base_delay
      @max_delay = max_delay
      @random = random
    end

    def decide(error:, attempt_number:, capabilities:, now:)
      return Decision.new(action: :unknown, at: nil) if unknown_without_idempotency?(error, capabilities)
      return Decision.new(action: :fail, at: nil) unless retryable?(error, capabilities)
      return exhausted(error) if attempt_number >= max_attempts

      Decision.new(action: :retry, at: now + delay(attempt_number, error.retry_after))
    end

    # Exponential backoff with "equal jitter": half fixed, half random, so retries
    # from many messages spread out but never collapse to ~0s.
    def delay(attempt_number, retry_after = nil)
      backoff = [@base_delay * (2**(attempt_number - 1)), @max_delay].min
      jittered = (backoff / 2.0) + (@random.rand * backoff / 2.0)
      retry_after ? [retry_after.to_f, jittered].max : jittered
    end

    private

    def unknown_without_idempotency?(error, capabilities)
      error.is_a?(UnknownOutcome) && !capabilities.idempotent_send
    end

    def retryable?(error, capabilities)
      RETRYABLE.any? { |klass| error.is_a?(klass) } ||
        (error.is_a?(UnknownOutcome) && capabilities.idempotent_send)
    end

    # Out of attempts: an UnknownOutcome stays unknown (it may have been delivered),
    # anything else is a definite failure.
    def exhausted(error)
      Decision.new(action: error.is_a?(UnknownOutcome) ? :unknown : :fail, at: nil)
    end
  end
end
