# frozen_string_literal: true

module NotifyKit
  # What a provider returns when the vendor ACCEPTED the message.
  # Acceptance is not delivery: delivery is only known from vendor callbacks.
  ProviderResponse = Data.define(:provider_message_id, :metadata) do
    def initialize(provider_message_id: nil, metadata: {})
      super(provider_message_id: provider_message_id&.to_s, metadata: metadata.freeze)
    end
  end
end
