# frozen_string_literal: true

module NotifyKit
  # The public API. Thin by design: builds value objects and calls services.
  #
  #   result = client.deliver(to: "0987654321", template: "212345", data: { order: "A1" },
  #                           idempotency_key: "order:1:paid")
  #   result.success?     # persisted (or already existed)
  #   result[:message_id] # use with #status / #attempts
  #   result[:duplicate]  # true when the idempotency key was seen before
  class Client
    attr_reader :configuration, :providers

    def initialize(configuration = NotifyKit.configuration)
      @configuration = configuration
      @providers = configuration.build_providers
    end

    # Request a notification. Returns quickly: delivery happens via the dispatcher
    # (inline by default) and is retried according to the RetryPolicy.
    # @return [NotifyKit::Result]
    def deliver(to:, provider: configuration.default_provider, template: nil, data: {}, content: nil,
                idempotency_key: nil)
      raise ConfigurationError, "no provider configured" if provider.nil?

      message = Message.new(provider:, to:, template:, data:, content:, idempotency_key:,
                            namespace: configuration.namespace)
      Services::Messages::Enqueue.call(
        message:, providers:, storage:, now: configuration.clock.call,
        on_commit: ->(id) { configuration.dispatcher.call(self, id) }
      )
    end

    # Process specific messages (used by dispatchers).
    def dispatch(ids:) = run_dispatch(ids:, limit: ids.size)

    # Process whatever is due. Run from a poller / recurring job; this is what
    # guarantees progress even when a dispatcher kick was lost.
    def dispatch_due(limit: 50) = run_dispatch(ids: nil, limit:)

    # @return [NotifyKit::StoredMessage, nil]
    def status(message_id) = storage.find(message_id)

    # @return [Array<NotifyKit::Attempt>]
    def attempts(message_id) = storage.attempts(message_id)

    private

    def storage = configuration.storage

    def run_dispatch(ids:, limit:)
      Services::Outbox::Dispatch.call(
        storage:, providers:, retry_policy: configuration.retry_policy, clock: configuration.clock,
        lease_seconds: configuration.lease_seconds, limit:, ids:
      )
    end
  end
end
