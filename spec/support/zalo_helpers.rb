# frozen_string_literal: true

# Builds Zalo providers wired to the mock server.
module ZaloHelpers
  # Conformance modes => mock server behaviours.
  MOCK_MODES = { ok: :ok, rate_limited: :rate_limited, lost_response: :lost_response, not_sent: :bad_gateway }.freeze

  def zalo_mock = MockServers::Zalo.instance

  def zalo_token_store(access: "access-1", refresh: "refresh-1", expires_in: 3600)
    NotifyKit::TokenStores::Memory.new(
      "shop_zalo" => NotifyKit::Token.new(access_token: access, refresh_token: refresh,
                                          expires_at: Time.now.utc + expires_in)
    )
  end

  def zalo_provider(klass = NotifyKit::Providers::Zalo::Zns, token_store: zalo_token_store, **)
    klass.new(name: :shop_zalo, transport: NotifyKit::Transports::NetHttp.new(read_timeout: 0.5),
              app_id: "app-id", app_secret: "app-secret", token_store:, urls: zalo_mock.urls, **)
  end
end

RSpec.configure do |config|
  config.include ZaloHelpers
end
