# frozen_string_literal: true

module NotifyKit
  module Records
    # OAuth tokens shared by every process using the same provider account.
    # Tip: enable ActiveRecord encryption in the host app and add
    #   NotifyKit::Records::ProviderToken.encrypts :access_token, :refresh_token
    class ProviderToken < ApplicationRecord
      self.table_name = "notify_kit_provider_tokens"

      validates :key, presence: true

      def to_token
        return nil if access_token.nil?

        Token.new(access_token:, refresh_token:, expires_at:)
      end

      def assign_token(token)
        assign_attributes(access_token: token.access_token, refresh_token: token.refresh_token,
                          expires_at: token.expires_at)
      end

      # Keep secrets out of logs and consoles.
      def inspect = "#<NotifyKit::Records::ProviderToken key=#{key.inspect} expires_at=#{expires_at.inspect}>"
    end
  end
end
