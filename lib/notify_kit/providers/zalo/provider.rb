# frozen_string_literal: true

module NotifyKit
  module Providers
    module Zalo
      # Shared plumbing for every Zalo provider type: HTTP client, error mapping and
      # token management. Subclasses only describe their message shape.
      class Provider < Base
        # @param app_id [String] Zalo app id
        # @param app_secret [String] Zalo app secret (OAuth `secret_key` header)
        # @param token_store [Ports::TokenStore] where the OA access/refresh tokens live
        # @param urls [Hash] override :oauth / :business / :openapi base URLs (mock servers)
        # @param error_codes [Hash{Integer=>Symbol}] extra Zalo code => category mappings
        def initialize(app_id:, app_secret:, token_store:, urls: {}, error_codes: {}, token_key: nil, **)
          super(**)
          raise ConfigurationError, "#{self.class}: transport is required" unless transport

          @client = Client.new(transport:, app_id:, app_secret:, urls:, error_mapper: ErrorMapper.new(error_codes))
          @tokens = TokenManager.new(key: token_key || name, client: @client, token_store:, clock:)
        end

        private

        attr_reader :client

        # Runs the request with the current token; on an expired/invalid token,
        # refreshes once and retries. Safe: Zalo rejected the first request, so it
        # was not delivered.
        # (Locals only: one provider instance is shared by all worker threads.)
        def with_access_token
          token = @tokens.access_token
          begin
            yield token
          rescue AuthFailure => e
            raise unless e.token_expired?

            yield @tokens.refresh!(stale_access_token: token)
          end
        end
      end
    end
  end
end
