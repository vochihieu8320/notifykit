# frozen_string_literal: true

module NotifyKit
  module Ports
    # Persists OAuth tokens for providers that need them (Zalo OA).
    # `with_lock` must serialise refreshes ACROSS PROCESSES for the same key, because
    # Zalo refresh tokens are single-use: two concurrent refreshes burn the token.
    module TokenStore
      # @return [Token, nil]
      def fetch(key)
        raise NotImplementedError
      end

      def save(key, token)
        raise NotImplementedError
      end

      # Yields the current token while holding an exclusive lock for `key`.
      # If the block returns a Token it is saved before the lock is released.
      # @return the block's value
      def with_lock(key)
        raise NotImplementedError
      end
    end
  end
end
