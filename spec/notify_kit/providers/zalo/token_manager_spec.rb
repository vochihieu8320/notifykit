# frozen_string_literal: true

RSpec.describe NotifyKit::Providers::Zalo::TokenManager do
  # The single-use refresh token race: N workers hit an expired token at once.
  context "when 10 threads find the access token expired at the same time" do
    it "calls the refresh endpoint exactly once and every send succeeds" do
      zalo_mock.reset!(access_token: "access-1", refresh_token: "refresh-1", refresh_delay: 0.2)
      store = zalo_token_store
      zalo_mock.expire_access_token!
      provider = zalo_provider(token_store: store)
      message = NotifyKit::Message.new(provider: :shop_zalo, to: "0912345678", template: "231802")

      errors = Array.new(10) do |i|
        Thread.new do
          provider.deliver(message, NotifyKit::DeliveryContext.new(message_id: i, attempt_number: 1))
          nil
        rescue NotifyKit::Error => e
          e
        end
      end.map(&:value)

      aggregate_failures do
        expect(errors.compact).to be_empty
        expect(zalo_mock.refresh_calls).to eq(1)
        expect(zalo_mock.sent.size).to eq(10)
      end
    end
  end
end
