# frozen_string_literal: true

require_relative "lib/notify_kit/version"

Gem::Specification.new do |spec|
  spec.name = "notify_kit"
  spec.version = NotifyKit::VERSION
  spec.authors = ["vochihieu8320"]
  spec.email = ["chihieu8320@gmail.com"]

  spec.summary = "Reliable notifications (Zalo first) with idempotency, safe retry and a transactional outbox."
  spec.description = <<~DESC
    NotifyKit sends notifications through pluggable providers (Zalo ZNS/OA first) on the host
    application's own infrastructure: dedup via idempotency keys, safe retry with an explicit
    error taxonomy, and a transactional outbox when used with ActiveRecord.
  DESC
  spec.homepage = "https://github.com/vochihieu8320/notify_kit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  # The only runtime dependency. ActiveRecord / ActiveJob / Railties come from the host app.
  spec.add_dependency "zeitwerk", "~> 2.6"
end
