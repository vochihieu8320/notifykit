# frozen_string_literal: true

module NotifyKit
  # OAuth token pair. `expires_at` may be nil when unknown.
  Token = Data.define(:access_token, :refresh_token, :expires_at) do
    def initialize(access_token:, refresh_token: nil, expires_at: nil)
      super
    end

    def expires_within?(seconds, now:)
      !expires_at.nil? && expires_at - seconds <= now
    end

    # Never leak secrets through logs or exception messages.
    def inspect = "#<NotifyKit::Token expires_at=#{expires_at.inspect}>"
    alias_method :to_s, :inspect
  end
end
