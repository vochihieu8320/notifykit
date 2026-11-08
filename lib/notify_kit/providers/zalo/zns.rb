# frozen_string_literal: true

module NotifyKit
  module Providers
    module Zalo
      # Zalo Notification Service / ZBS template message: approved template sent to
      # a PHONE NUMBER. Requires a verified OA, approved templates and prepaid quota.
      #
      #   c.provider :shop_zalo, :zalo_zns, app_id: "...", app_secret: "...", token_store: store
      #   NotifyKit.deliver(provider: :shop_zalo, to: "0912345678", template: "231802",
      #                     data: { customer_name: "An", order_code: "A1" })
      #
      # Zalo has no idempotency key, so a lost response is UnknownOutcome. We pass our
      # message id as `tracking_id`, which lets an operator reconcile later.
      class Zns < Provider
        def capabilities
          Capabilities.new(channel: :zalo, recipient_kind: :phone, templates: true,
                           idempotent_send: false, tracking_id: true)
        end

        def validate!(message)
          Support::VnPhone.normalize!(message.to)
          raise InvalidTemplate, "ZNS requires a template id" if message.template.to_s.strip.empty?
          raise InvalidTemplate, "ZNS template data must be a Hash" unless message.data.is_a?(Hash)
        end

        def deliver(message, context)
          body = with_access_token do |token|
            client.send_template(access_token: token, phone: Support::VnPhone.normalize(message.to),
                                 template_id: message.template, template_data: message.data,
                                 tracking_id: context.message_id.to_s)
          end
          data = body["data"] || {}
          ProviderResponse.new(provider_message_id: data["msg_id"], metadata: { "quota" => data["quota"] })
        end
      end
    end
  end
end
