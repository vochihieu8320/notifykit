# frozen_string_literal: true

module NotifyKit
  module Records
    # One logical notification. This row is also the transactional-outbox entry:
    # it is written in the caller's transaction and dispatched after commit.
    class Message < ApplicationRecord
      self.table_name = "notify_kit_messages"

      include Concerns::Idempotent
      include Concerns::Leasable
      include Concerns::StateMachine

      has_many :delivery_attempts, class_name: "NotifyKit::Records::DeliveryAttempt",
                                   inverse_of: :message, dependent: :delete_all

      validates :namespace, :provider, :recipient, :available_at, presence: true

      after_commit :run_commit_hooks, on: :create

      # Run `block` after the surrounding transaction commits (never on rollback).
      def on_commit(&block)
        (@commit_hooks ||= []) << block
      end

      def to_stored
        StoredMessage.new(
          id:, namespace:, idempotency_key:, fingerprint: payload_fingerprint, provider: provider.to_sym,
          to: recipient, template:, data: data || {}, content:, state:, attempts_count:, available_at:,
          locked_by:, locked_until:, provider_message_id:, last_error_category:, last_error_message:,
          created_at:, updated_at:
        )
      end

      private

      def run_commit_hooks
        hooks = @commit_hooks || []
        @commit_hooks = nil
        hooks.each(&:call)
      end
    end
  end
end
