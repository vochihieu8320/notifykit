# frozen_string_literal: true

module NotifyKit
  # Processes one committed message on the host app's ActiveJob backend
  # (Sidekiq, GoodJob, SolidQueue, ...). Safe to run twice: claiming is atomic,
  # so a duplicate job simply finds nothing to claim.
  class DispatchJob < ::ActiveJob::Base
    queue_as :notify_kit

    def perform(message_id)
      NotifyKit.client.dispatch(ids: [message_id])
    end
  end
end
