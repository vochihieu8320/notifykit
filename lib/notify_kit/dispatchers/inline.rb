# frozen_string_literal: true

module NotifyKit
  module Dispatchers
    # Processes the message right after it is committed, in the caller's thread.
    # Good for scripts, tests and the Memory store. In web apps prefer ActiveJob.
    class Inline
      include Ports::Dispatcher

      def call(client, message_id)
        client.dispatch(ids: [message_id])
      end
    end
  end
end
