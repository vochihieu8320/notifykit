# frozen_string_literal: true

RSpec.describe NotifyKit::Providers::Zalo::OaMessage do
  before { zalo_mock.reset! }

  it_behaves_like "a NotifyKit provider" do
    let(:provider_for) do
      ->(mode) { zalo_mock.enqueue(ZaloHelpers::MOCK_MODES.fetch(mode)) && zalo_provider(described_class) }
    end
    let(:valid_message) { NotifyKit::Message.new(provider: :shop_zalo, to: "1234567890", content: "Xin chào") }
    let(:invalid_message) { NotifyKit::Message.new(provider: :shop_zalo, to: "1234567890", content: "") }
  end
end
