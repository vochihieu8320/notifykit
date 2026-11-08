# frozen_string_literal: true

module NotifyKit
  # Configured provider instances, looked up by instance name.
  class ProviderSet
    def initialize(providers)
      @providers = providers.transform_keys(&:to_sym).freeze
    end

    def fetch(name)
      @providers.fetch(name.to_sym) do
        raise ConfigurationError, "no provider named #{name.inspect}; configured: #{@providers.keys.join(', ')}"
      end
    end

    def names = @providers.keys
  end
end
