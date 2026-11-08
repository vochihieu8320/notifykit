# frozen_string_literal: true

module NotifyKit
  module Providers
    module Zalo
      # OA consultation ("tin tư vấn") text message to a follower's user_id.
      # Only allowed within Zalo's interaction window after the user contacted the OA.
      #
      #   c.provider :support_oa, :zalo_oa, app_id: "...", app_secret: "...", token_store: store
      #   NotifyKit.deliver(provider: :support_oa, to: "<zalo user_id>", content: "Xin chào!")
      class OaMessage < Provider
        def capabilities
          Capabilities.new(channel: :zalo, recipient_kind: :user_id, templates: false,
                           idempotent_send: false, tracking_id: false)
        end

        def validate!(message)
          raise InvalidRecipient, "Zalo user_id must be numeric" unless message.to.match?(/\A\d+\z/)
          raise InvalidTemplate, "OA message requires text content" if message.content.to_s.strip.empty?
        end

        def deliver(message, _context)
          body = with_access_token do |token|
            client.send_text(access_token: token, user_id: message.to, text: message.content)
          end
          ProviderResponse.new(provider_message_id: body.dig("data", "message_id"))
        end
      end
    end
  end
end
