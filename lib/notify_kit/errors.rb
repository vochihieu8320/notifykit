# frozen_string_literal: true

module NotifyKit
  # Root of every error raised by NotifyKit. Host apps can `rescue NotifyKit::Error`.
  class Error < StandardError; end

  # Misconfiguration (unknown provider key, missing credentials, ...). A programmer error.
  class ConfigurationError < Error; end

  # Same idempotency key reused with a different payload. Nothing is sent.
  class IdempotencyConflict < Error
    attr_reader :message_id

    def initialize(msg = nil, message_id: nil)
      super(msg)
      @message_id = message_id
    end
  end

  # Base class of the delivery error taxonomy. Providers translate vendor-specific
  # responses into exactly one of these subclasses; services decide retry/fallback
  # from the class alone, never from vendor codes.
  class DeliveryError < Error
    attr_reader :provider_code, :retry_after

    def initialize(msg = nil, provider_code: nil, retry_after: nil)
      super(msg)
      @provider_code = provider_code
      @retry_after = retry_after
    end

    def category = self.class.category

    class << self
      def category
        name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
      end
    end
  end

  # Provider throttled us. `retry_after` (seconds) is honoured when present.
  class RateLimited < DeliveryError; end

  # Credentials/token rejected. `token_expired?` lets providers refresh once.
  class AuthFailure < DeliveryError
    def initialize(msg = nil, token_expired: false, **)
      super(msg, **)
      @token_expired = token_expired
    end

    def token_expired? = @token_expired
  end

  # Recipient cannot receive on this channel (bad phone, not a Zalo user, blocked OA, ...).
  class InvalidRecipient < DeliveryError; end
  # Template missing/unapproved or template data does not match.
  class InvalidTemplate < DeliveryError; end
  # Policy forbids sending (quota exhausted, outside messaging window, opt-in missing).
  class NotEligible < DeliveryError; end
  # The request provably did NOT reach the provider (connect failure, 502/503/504). Safe to retry.
  class TransientFailure < DeliveryError; end
  # The request MAY have reached the provider (read timeout, reset after write, 500).
  # Retrying risks a duplicate; only done when the provider supports idempotent sends.
  class UnknownOutcome < DeliveryError; end
  # Anything else the provider rejected for good.
  class PermanentFailure < DeliveryError; end
end
