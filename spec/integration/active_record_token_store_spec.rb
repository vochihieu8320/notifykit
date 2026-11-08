# frozen_string_literal: true

require "active_record_helper"

RSpec.describe NotifyKit::TokenStores::ActiveRecordStore, :db do
  subject(:store) { described_class.new }

  let(:token) { NotifyKit::Token.new(access_token: "access-1", refresh_token: "refresh-1", expires_at: Time.now.utc + 3600) }

  it "round-trips a token" do
    store.save(:shop_zalo, token)
    expect(store.fetch("shop_zalo").refresh_token).to eq("refresh-1")
  end

  it "does not expose secrets in inspect" do
    store.save(:shop_zalo, token)
    expect(NotifyKit::Records::ProviderToken.last.inspect).not_to include("access-1")
  end

  # Refresh tokens are single-use: concurrent refreshes across workers must
  # collapse into one call, coordinated through the database row lock.
  context "when 10 workers hit an expired Zalo token at once" do
    it "refreshes exactly once" do
      zalo_mock.reset!(refresh_delay: 0.2)
      store.save(:shop_zalo, token)
      zalo_mock.expire_access_token!
      message = NotifyKit::Message.new(provider: :shop_zalo, to: "0912345678", template: "231802")

      errors = in_threads(10) do |i|
        context = NotifyKit::DeliveryContext.new(message_id: i, attempt_number: 1)
        zalo_provider(token_store: store).deliver(message, context)
        nil
      rescue NotifyKit::Error => e
        e
      end

      aggregate_failures do
        expect(errors.compact).to be_empty
        expect(zalo_mock.refresh_calls).to eq(1)
        expect(store.fetch(:shop_zalo).refresh_token).to eq("refresh-2")
      end
    end
  end
end
