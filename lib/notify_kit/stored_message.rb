# frozen_string_literal: true

module NotifyKit
  # Snapshot of a persisted message as returned by any Storage adapter.
  # Services only ever see this value object, never an ActiveRecord model,
  # so they work the same with every adapter.
  StoredMessage = Data.define(
    :id, :namespace, :idempotency_key, :fingerprint, :provider, :to, :template, :data, :content,
    :state, :attempts_count, :available_at, :locked_by, :locked_until,
    :provider_message_id, :last_error_category, :last_error_message, :created_at, :updated_at
  ) do
    def to_message
      Message.new(provider:, to:, template:, data:, content:, idempotency_key:, namespace:)
    end

    def terminal? = States::TERMINAL.include?(state)
  end
end
