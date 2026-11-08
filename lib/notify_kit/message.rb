# frozen_string_literal: true

require "digest"
require "json"

module NotifyKit
  # Immutable description of ONE logical notification requested by the host app.
  #
  # `provider` is a provider *instance* name from the configuration (e.g. :shop_zalo),
  # not a provider type. `fingerprint` identifies the payload so that reusing an
  # idempotency key with different content can be detected.
  Message = Data.define(:provider, :to, :template, :data, :content, :idempotency_key, :namespace) do
    def initialize(provider:, to:, template: nil, data: {}, content: nil, idempotency_key: nil, namespace: "default")
      super(
        provider: provider.to_sym,
        to: to.to_s,
        template: template&.to_s,
        data: Message.deep_stringify(data || {}).freeze,
        content: content,
        idempotency_key: idempotency_key&.to_s,
        namespace: namespace.to_s
      )
    end

    def fingerprint
      payload = { "provider" => provider.to_s, "to" => to, "template" => template, "data" => data,
                  "content" => content }
      Digest::SHA256.hexdigest(JSON.generate(Message.canonical(payload)))
    end

    class << self
      def deep_stringify(value)
        case value
        when Hash then value.to_h { |k, v| [k.to_s, deep_stringify(v)] }
        when Array then value.map { |v| deep_stringify(v) }
        when Symbol then value.to_s
        else value
        end
      end

      # Sorted keys at every level => same payload, same fingerprint, regardless of key order.
      def canonical(value)
        case value
        when Hash then value.keys.sort.to_h { |k| [k, canonical(value[k])] }
        when Array then value.map { |v| canonical(v) }
        else value
        end
      end
    end
  end
end
