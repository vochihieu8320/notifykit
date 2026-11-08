# frozen_string_literal: true

module NotifyKit
  # Holds adapters, providers and policies. Everything has a working default, so
  # the minimal setup is just declaring a provider.
  #
  #   NotifyKit.configure do |c|
  #     c.storage    = NotifyKit::Storage::ActiveRecordStorage.new   # default: Storage::Memory
  #     c.dispatcher = NotifyKit::Dispatchers::ActiveJobDispatcher.new # default: Dispatchers::Inline
  #     c.provider :shop_zalo, :zalo_zns, app_id: ENV["ZALO_APP_ID"], app_secret: ENV["ZALO_APP_SECRET"],
  #                                       token_store: NotifyKit::TokenStores::ActiveRecordStore.new
  #     c.default_provider = :shop_zalo
  #     c.retry_policy = NotifyKit::RetryPolicy.new(max_attempts: 5)
  #   end
  class Configuration
    attr_accessor :storage, :dispatcher, :default_provider, :namespace, :lease_seconds,
                  :retry_policy, :clock, :transport
    attr_reader :provider_definitions

    def initialize
      @storage = Storage::Memory.new
      @dispatcher = Dispatchers::Inline.new
      @namespace = "default"
      @lease_seconds = 60
      @retry_policy = RetryPolicy.new
      @clock = -> { Time.now.utc }
      @transport = Transports::NetHttp.new
      @provider_definitions = {}
    end

    # Declare a provider instance.
    # @param name [Symbol] instance name you will refer to (e.g. :shop_a_zalo)
    # @param type [Symbol] provider type key from Providers::Registry (e.g. :zalo_zns)
    def provider(name, type, **options)
      @provider_definitions[name.to_sym] = { type: type.to_sym, options: options }
      @default_provider ||= name.to_sym
      self
    end

    def build_providers
      ProviderSet.new(
        @provider_definitions.to_h do |name, definition|
          [name, Providers::Registry.build(name:, type: definition[:type], options: definition[:options],
                                           transport: @transport, clock: @clock)]
        end
      )
    end
  end
end
