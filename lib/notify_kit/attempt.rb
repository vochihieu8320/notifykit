# frozen_string_literal: true

module NotifyKit
  # One physical call to a provider.
  # outcome: nil while in flight, then "accepted" | "failed" | "unknown".
  Attempt = Data.define(
    :id, :message_id, :number, :provider, :outcome, :error_category, :error_message,
    :provider_message_id, :started_at, :finished_at
  ) do
    def in_flight? = finished_at.nil?
  end
end
