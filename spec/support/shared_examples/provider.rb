# frozen_string_literal: true

# The provider contract. Every provider type must pass this; adding a provider
# means adding one spec file in spec/conformance that includes it.
#
# Required lets:
#   provider_for  ->(mode) { provider } where mode is one of
#                 :ok, :rate_limited, :lost_response, :not_sent
#   valid_message NotifyKit::Message the provider accepts
#   invalid_message NotifyKit::Message the provider must reject in validate!
RSpec.shared_examples "a NotifyKit provider" do
  let(:context) { NotifyKit::DeliveryContext.new(message_id: 42, attempt_number: 1) }

  it "declares capabilities" do
    expect(provider_for.call(:ok).capabilities).to be_a(NotifyKit::Capabilities)
  end

  it "accepts a valid message in validate!" do
    expect { provider_for.call(:ok).validate!(valid_message) }.not_to raise_error
  end

  it "rejects an invalid message in validate! with a delivery error" do
    expect { provider_for.call(:ok).validate!(invalid_message) }.to raise_error(NotifyKit::DeliveryError)
  end

  it "returns a ProviderResponse when the vendor accepts" do
    expect(provider_for.call(:ok).deliver(valid_message, context)).to be_a(NotifyKit::ProviderResponse)
  end

  it "raises RateLimited when throttled" do
    expect { provider_for.call(:rate_limited).deliver(valid_message, context) }
      .to raise_error(NotifyKit::RateLimited)
  end

  it "raises UnknownOutcome when the response is lost after sending" do
    expect { provider_for.call(:lost_response).deliver(valid_message, context) }
      .to raise_error(NotifyKit::UnknownOutcome)
  end

  it "raises TransientFailure when the request provably was not processed" do
    expect { provider_for.call(:not_sent).deliver(valid_message, context) }
      .to raise_error(NotifyKit::TransientFailure)
  end
end
