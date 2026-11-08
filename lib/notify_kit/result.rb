# frozen_string_literal: true

module NotifyKit
  # Return value of public API calls and services: success with a value hash, or failure
  # with an error. Expected business outcomes are Results; programmer errors raise.
  Result = Data.define(:value, :error) do
    def self.success(**value) = new(value: value.freeze, error: nil)
    def self.failure(error, **value) = new(value: value.freeze, error: error)

    def success? = error.nil?
    def failure? = !success?
    def [](key) = value[key]
  end
end
