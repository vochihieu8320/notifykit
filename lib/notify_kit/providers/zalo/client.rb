# frozen_string_literal: true

module NotifyKit
  module Providers
    module Zalo
      # Thin HTTP client for the Zalo endpoints NotifyKit uses. Base URLs are
      # configurable so specs (and staging) can point at a mock server.
      #
      # Endpoints follow Zalo's public docs and community SDKs; verify against
      # developers.zalo.me when wiring real credentials.
      class Client
        DEFAULT_URLS = {
          oauth: "https://oauth.zaloapp.com",
          business: "https://business.openapi.zalo.me",
          openapi: "https://openapi.zalo.me"
        }.freeze

        def initialize(transport:, app_id:, app_secret:, error_mapper:, urls: {})
          @transport = transport
          @app_id = app_id.to_s
          @app_secret = app_secret.to_s
          @error_mapper = error_mapper
          @urls = DEFAULT_URLS.merge(urls.transform_keys(&:to_sym))
        end

        # ZNS / ZBS template message to a phone number.
        def send_template(access_token:, phone:, template_id:, template_data:, tracking_id:)
          post(:business, "/message/template", access_token,
               { phone:, template_id:, template_data:, tracking_id: })
        end

        # OA consultation message to a follower (user_id).
        def send_text(access_token:, user_id:, text:)
          post(:openapi, "/v3.0/oa/message/cs", access_token,
               { recipient: { user_id: }, message: { text: } })
        end

        # OAuth v4 refresh. The returned refresh_token REPLACES the old one
        # (refresh tokens are single-use).
        # @return [Hash] {"access_token", "refresh_token", "expires_in"}
        def refresh(refresh_token)
          response = @transport.post(
            "#{@urls[:oauth]}/v4/oa/access_token",
            headers: { "secret_key" => @app_secret },
            form: { app_id: @app_id, refresh_token:, grant_type: "refresh_token" }
          )
          body = response.json
          return body if response.status == 200 && body.is_a?(Hash) && body["access_token"]

          reason = body.is_a?(Hash) ? body["error_name"] || body["error"] : "HTTP #{response.status}"
          raise AuthFailure, "Zalo token refresh failed: #{reason}"
        end

        private

        def post(base, path, access_token, payload)
          url = "#{@urls[base]}#{path}"
          response = @transport.post(url, headers: { "access_token" => access_token }, json: payload)
          @error_mapper.check!(response)
        end
      end
    end
  end
end
