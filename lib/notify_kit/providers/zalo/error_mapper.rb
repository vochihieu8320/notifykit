# frozen_string_literal: true

module NotifyKit
  module Providers
    module Zalo
      # Translates Zalo HTTP responses into the NotifyKit error taxonomy.
      #
      # Zalo usually answers HTTP 200 with `{"error": <code>, "message": "..."}`;
      # `error == 0` means success.
      #
      # Only codes we could confirm are mapped by default. Every other non-zero code
      # becomes PermanentFailure (do not retry what we do not understand). Apps can
      # map more codes once verified against developers.zalo.me:
      #
      #   c.provider :shop_zalo, :zalo_zns, ..., error_codes: { -1234 => :rate_limited }
      class ErrorMapper
        # Confirmed from Zalo OA API usage (token invalid / expired).
        TOKEN_ERRORS = [-216, -220].freeze

        CATEGORIES = {
          rate_limited: RateLimited, auth_failure: AuthFailure, invalid_recipient: InvalidRecipient,
          invalid_template: InvalidTemplate, not_eligible: NotEligible, transient_failure: TransientFailure,
          unknown_outcome: UnknownOutcome, permanent_failure: PermanentFailure
        }.freeze

        def initialize(overrides = {})
          @overrides = overrides.transform_keys(&:to_i).transform_values do |category|
            CATEGORIES.fetch(category.to_sym) { raise ConfigurationError, "unknown error category #{category}" }
          end
        end

        # @return [Hash] parsed body on success
        def check!(response)
          check_http!(response)
          body = response.json
          # A 2xx we cannot parse: Zalo may have processed it.
          raise UnknownOutcome, "Zalo returned an unreadable body (HTTP #{response.status})" unless body.is_a?(Hash)

          code = body["error"].to_i
          return body if code.zero?

          raise error_for(code, body["message"])
        end

        private

        def check_http!(response)
          case response.status
          when 200..299 then nil
          when 429
            raise RateLimited.new("Zalo HTTP 429", retry_after: retry_after(response))
          when 502, 503, 504
            raise TransientFailure, "Zalo HTTP #{response.status} (gateway did not process the request)"
          when 500..599
            raise UnknownOutcome, "Zalo HTTP #{response.status}"
          else
            raise PermanentFailure, "Zalo HTTP #{response.status}" unless response.json.is_a?(Hash)
          end
        end

        def error_for(code, text)
          message = "Zalo error #{code}: #{text}"
          return AuthFailure.new(message, token_expired: true, provider_code: code) if TOKEN_ERRORS.include?(code)

          (@overrides[code] || PermanentFailure).new(message, provider_code: code)
        end

        def retry_after(response)
          value = Array(response.headers["retry-after"]).first
          value&.match?(/\A\d+\z/) ? value.to_i : nil
        end
      end
    end
  end
end
