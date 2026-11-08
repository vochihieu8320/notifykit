# frozen_string_literal: true

module NotifyKit
  module Dispatchers
    # Enqueues a DispatchJob once the message is committed.
    #
    # If enqueueing fails (Redis down, process killed right after commit) nothing is
    # lost: the message stays `queued` in the database and the poller
    # (`rake notify_kit:work` or a recurring `NotifyKit.dispatch_due`) delivers it.
    # That is the difference between an outbox and "enqueue in after_commit".
    class ActiveJobDispatcher
      include Ports::Dispatcher

      def initialize(job: DispatchJob, queue: nil)
        @job = job
        @queue = queue
      end

      def call(_client, message_id)
        (@queue ? @job.set(queue: @queue) : @job).perform_later(message_id)
      end
    end
  end
end
