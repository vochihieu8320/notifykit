# frozen_string_literal: true

module NotifyKit
  # Logical lifecycle of a message:
  #
  #   queued ──► sending ──► accepted
  #                │  ├────► retry_scheduled ──► sending ...
  #                │  ├────► failed           (terminal)
  #                │  └────► unknown_outcome  (terminal until reconciled)
  #                └─ lease expired ──► picked up by another worker
  module States
    QUEUED = "queued"
    SENDING = "sending"
    RETRY_SCHEDULED = "retry_scheduled"
    ACCEPTED = "accepted"
    FAILED = "failed"
    UNKNOWN_OUTCOME = "unknown_outcome"

    DISPATCHABLE = [QUEUED, RETRY_SCHEDULED].freeze
    TERMINAL = [ACCEPTED, FAILED, UNKNOWN_OUTCOME].freeze
    ALL = [QUEUED, SENDING, RETRY_SCHEDULED, ACCEPTED, FAILED, UNKNOWN_OUTCOME].freeze
  end
end
