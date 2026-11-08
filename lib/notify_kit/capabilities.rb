# frozen_string_literal: true

module NotifyKit
  # What a provider type can do. Services make decisions from capabilities,
  # never from `provider.is_a?(SomeVendor)`.
  #
  # idempotent_send: the vendor de-duplicates on a client key, so retrying an
  #                  UnknownOutcome cannot create a physical duplicate.
  # tracking_id:     the vendor stores our message id, enabling later reconciliation.
  Capabilities = Data.define(:channel, :recipient_kind, :templates, :idempotent_send, :tracking_id) do
    def initialize(channel:, recipient_kind:, templates: false, idempotent_send: false, tracking_id: false)
      super
    end
  end
end
