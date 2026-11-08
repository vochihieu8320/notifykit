# frozen_string_literal: true

module NotifyKit
  module Providers
    # Maps provider *type* keys (:zalo_zns) to classes.
    #
    # Built-ins are stored as class names so they stay lazily autoloaded; third-party
    # gems (e.g. a future notify_kit-esms) call `register` from their entry file:
    #
    #   NotifyKit::Providers::Registry.register(:esms_sms, NotifyKit::Esms::Sms)
    module Registry
      BUILT_IN = {
        fake: "NotifyKit::Providers::Fake",
        zalo_zns: "NotifyKit::Providers::Zalo::Zns",
        zalo_oa: "NotifyKit::Providers::Zalo::OaMessage"
      }.freeze

      @custom = {}
      @mutex = Mutex.new

      class << self
        def register(key, klass)
          unless klass.is_a?(Class) && klass <= Base
            raise ConfigurationError, "#{klass.inspect} must subclass NotifyKit::Providers::Base"
          end

          @mutex.synchronize { @custom[key.to_sym] = klass }
        end

        def fetch(key)
          key = key.to_sym
          klass = @mutex.synchronize { @custom[key] }
          return klass if klass
          return Object.const_get(BUILT_IN.fetch(key)) if BUILT_IN.key?(key)

          raise ConfigurationError, "unknown provider type #{key.inspect}; known: #{keys.join(', ')}"
        end

        def keys = (BUILT_IN.keys + @mutex.synchronize { @custom.keys }).uniq

        # Builds a provider instance from configuration.
        def build(name:, type:, options:, transport:, clock:)
          fetch(type).new(name: name, transport: transport, clock: clock, **options)
        end
      end
    end
  end
end
