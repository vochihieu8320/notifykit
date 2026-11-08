# frozen_string_literal: true

RSpec.describe NotifyKit::Providers::Zalo::Zns do
  before { zalo_mock.reset! }

  it_behaves_like "a NotifyKit provider" do
    let(:provider_for) { ->(mode) { zalo_mock.enqueue(ZaloHelpers::MOCK_MODES.fetch(mode)) && zalo_provider } }
    let(:valid_message) { NotifyKit::Message.new(provider: :shop_zalo, to: "0912345678", template: "231802") }
    let(:invalid_message) { NotifyKit::Message.new(provider: :shop_zalo, to: "12345", template: "231802") }
  end
end
