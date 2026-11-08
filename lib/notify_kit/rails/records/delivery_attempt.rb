# frozen_string_literal: true

module NotifyKit
  module Records
    # One physical provider call. Committed with finished_at = NULL *before* the HTTP
    # request, so an attempt left unfinished proves a worker died mid-request.
    class DeliveryAttempt < ApplicationRecord
      self.table_name = "notify_kit_delivery_attempts"

      belongs_to :message, class_name: "NotifyKit::Records::Message", inverse_of: :delivery_attempts

      validates :number, :provider, :started_at, presence: true

      scope :in_flight, -> { where(finished_at: nil) }

      def to_attempt
        Attempt.new(id:, message_id:, number:, provider:, outcome:, error_category:, error_message:,
                    provider_message_id:, started_at:, finished_at:)
      end
    end
  end
end
