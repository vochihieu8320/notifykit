# frozen_string_literal: true

module NotifyKit
  module Providers
    module Zalo
      # Hands out a valid OA access token and refreshes it safely.
      #
      # Zalo refresh tokens are SINGLE-USE. If two workers refresh with the same
      # refresh token, the second call fails and the OA must be re-authorised by a
      # human. So every refresh runs under TokenStore#with_lock, and inside the lock
      # we first check whether another worker already refreshed (the stored access
      # token differs from the one that just failed) before calling Zalo.
      class TokenManager
        def initialize(key:, client:, token_store:, clock:, refresh_before: 300)
          @key = key.to_s
          @client = client
          @token_store = token_store
          @clock = clock
          @refresh_before = refresh_before
        end

        def access_token
          token = @token_store.fetch(@key)
          raise ConfigurationError, "no Zalo token for #{@key.inspect}; run the OAuth flow first" unless token

          expiring = token.expires_within?(@refresh_before, now: @clock.call)
          expiring ? refresh!(stale_access_token: token.access_token) : token.access_token
        end

        # @param stale_access_token [String] the token that was rejected/expiring
        # @return [String] a fresh access token
        def refresh!(stale_access_token:)
          @token_store.with_lock(@key) do |current|
            next current if current && current.access_token != stale_access_token # someone already refreshed
            raise ConfigurationError, "no refresh token stored for #{@key.inspect}" unless current&.refresh_token

            body = @client.refresh(current.refresh_token)
            Token.new(access_token: body["access_token"], refresh_token: body["refresh_token"],
                      expires_at: @clock.call + body["expires_in"].to_i)
          end.access_token
        end
      end
    end
  end
end
