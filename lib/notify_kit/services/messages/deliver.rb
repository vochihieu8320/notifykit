# frozen_string_literal: true

module NotifyKit
  module Services
    module Messages
      # Performs ONE provider call and guarantees the caller only ever sees a
      # ProviderResponse or a NotifyKit::DeliveryError.
      #
      # Any unexpected exception raised by provider code during `deliver` is treated as
      # UnknownOutcome: we cannot prove the request did not reach the vendor, and the
      # safe default is "don't blindly resend".
      class Deliver
        def self.call(...) = new(...).call

        def initialize(message:, provider:, context:)
          @message = message
          @provider = provider
          @context = context
        end

        def call
          @provider.validate!(@message)
          begin
            @provider.deliver(@message, @context)
          rescue DeliveryError
            raise
          rescue StandardError => e
            raise UnknownOutcome, "#{@provider.class} raised #{e.class}: #{e.message}"
          end
        end
      end
    end
  end
end
