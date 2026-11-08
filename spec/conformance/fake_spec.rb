# frozen_string_literal: true

RSpec.describe NotifyKit::Providers::Fake do
  it_behaves_like "a NotifyKit provider" do
    let(:outcome_for) do
      { ok: :ok, rate_limited: NotifyKit::RateLimited, lost_response: NotifyKit::UnknownOutcome,
        not_sent: NotifyKit::TransientFailure }
    end
    let(:provider_for) do
      ->(mode) { described_class.new(name: :fake, outcomes: [outcome_for.fetch(mode)], invalid_recipients: ["x"]) }
    end
    let(:valid_message) { NotifyKit::Message.new(provider: :fake, to: "0912345678") }
    let(:invalid_message) { NotifyKit::Message.new(provider: :fake, to: "x") }
  end
end
