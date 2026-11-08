# frozen_string_literal: true

module NotifyKit
  module TokenStores
    # Process-local token store. Fine for a single process; use the ActiveRecord
    # store when several processes/workers share one Zalo OA.
    class Memory
      include Ports::TokenStore

      def initialize(tokens = {})
        @tokens = tokens.transform_keys(&:to_s)
        @locks = Hash.new { |h, k| h[k] = Mutex.new }
        @guard = Mutex.new
      end

      def fetch(key) = @guard.synchronize { @tokens[key.to_s] }

      def save(key, token)
        @guard.synchronize { @tokens[key.to_s] = token }
      end

      def with_lock(key)
        lock = @guard.synchronize { @locks[key.to_s] }
        lock.synchronize do
          result = yield fetch(key)
          save(key, result) if result.is_a?(Token)
          result
        end
      end
    end
  end
end
