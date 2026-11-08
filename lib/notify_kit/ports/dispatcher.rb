# frozen_string_literal: true

module NotifyKit
  module Ports
    # Decides HOW a freshly committed message gets processed.
    # A dispatcher is only a fast path ("kick"): correctness never depends on it,
    # because `NotifyKit.dispatch_due` (poller / recurring job) picks up anything
    # a lost kick left behind.
    module Dispatcher
      def call(client, message_id)
        raise NotImplementedError
      end
    end
  end
end
