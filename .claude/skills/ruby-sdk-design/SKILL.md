---
name: ruby-sdk-design
description: Architecture rules for the NotifyKit Ruby gem — layering (public API → services → ports → adapters/providers), provider plugin contract & registry, Railtie/generators, dependency policy, and the checklist for adding a new provider. Use when creating files under lib/, adding a provider/adapter, or changing public API.
---

# Ruby SDK design (NotifyKit)

Full rationale: `docs/architecture.md`. This skill is the enforceable summary.

## Layering — dependencies point inward only

```
Public API      NotifyKit.configure / NotifyKit::Client#deliver
   ↓
Services        lib/notify_kit/services/**   (Deliver, Enqueue, Dispatch, RetryPolicy, Reconcile)
   ↓ uses ports (duck-typed contracts in lib/notify_kit/ports/**)
Ports           Storage, Dispatcher, TokenStore, HttpTransport, Clock, Instrumenter
   ↑ implemented by
Adapters        lib/notify_kit/storage/{memory,active_record}, dispatchers/{inline,active_job}
Providers       lib/notify_kit/providers/<vendor>/**   (zalo, esms, ses, …)
Rails glue      lib/notify_kit/rails/** (Railtie, generators, models, ErrorHandler) — optional
```

- Core (`lib/notify_kit.rb` + services + ports + memory adapter) must load **without Rails**.
  `require "notify_kit"` must not require `rails`, `active_record`, or any provider SDK.
- Rails glue only loads when `defined?(Rails::Railtie)`.
- Services never reference a concrete provider or adapter class — only ports + registry.
- Providers never touch storage; they take a message, return a `ProviderResponse` or raise a
  categorized `NotifyKit::Error`.

## Provider contract

```ruby
class NotifyKit::Providers::Base
  def self.key            # :zalo_zns — unique registry key
  def capabilities        # NotifyKit::Capabilities (channel, recipient_kind, templates?, idempotent_send?, tracking_id?)
  def validate!(message)  # raise InvalidRecipient/InvalidTemplate/NotEligible BEFORE any HTTP
  def deliver(message, context) # → ProviderResponse(provider_message_id:, raw_status:, metadata:)
end
```

Registration: `NotifyKit::Providers.register(:zalo_zns, NotifyKit::Providers::Zalo::Zns)`.
Users pick providers by key in config; services look them up via the registry.

## Folder per vendor, file per responsibility

```
lib/notify_kit/providers/zalo/
├── zns.rb              # provider (template msg to phone)
├── oa_message.rb       # provider (consultation msg to user_id)
├── client.rb           # thin HTTP client (uses HttpTransport port)
├── error_mapper.rb     # Zalo error codes → NotifyKit errors
├── phone_number.rb     # VN normalization (0xxx/+84 → 84xxx)
└── token_manager.rb    # access/refresh token via TokenStore port + lock
```

Shared vendor-agnostic helpers (phone normalization for VN, retry-after parsing) live in
`lib/notify_kit/support/`, not inside one vendor's folder.

## Dependency policy

- Runtime deps: zero or near-zero. Use stdlib `net/http` behind `HttpTransport`; Faraday only as
  an optional adapter. `zeitwerk` is acceptable for autoloading.
- ActiveRecord/ActiveJob/Railties are **not** gemspec runtime deps; they are present in the
  host app. Declare them as development deps for the dummy app.
- Ask the user before adding any dependency.

## Rails integration rules

- Migrations ship via generator `rails g notify_kit:install`; never auto-run at boot.
- Host model/table names configurable; no hard-coded `::User`.
- Initializers idempotent (safe on code reload).
- Outbox writes use the host app's ActiveRecord connection so they join the caller's transaction.

## Public API stability

- Everything not documented in README is private (`# @api private`).
- Value objects (`Message`, `Result`, `ProviderResponse`) are immutable (`Data.define` / frozen).
- Never break the public API without a CHANGELOG entry.

## Checklist — adding a provider

1. `lib/notify_kit/providers/<vendor>/` with provider class(es) subclassing `Base`.
2. Declare `capabilities`; implement `validate!` (no HTTP) and `deliver`.
3. `error_mapper.rb` covering: success, auth/token, rate limit (+retry_after), invalid recipient,
   invalid template, quota/not eligible, 5xx, timeout-before-send, timeout-after-send.
4. Register the key; document config keys in README.
5. Mock server `spec/support/mock_servers/<vendor>.rb` with failure modes.
6. `spec/conformance/<vendor>_spec.rb` → `it_behaves_like "a NotifyKit provider"`.
7. No change to services required — if one is needed, the abstraction is wrong; stop and discuss.
