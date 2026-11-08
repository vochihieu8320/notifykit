<p align="center">
  <img src="branding/logo-240.png" width="96" alt="NotifyKit logo">
</p>

<h1 align="center">NotifyKit</h1>

<p align="center">
  Reliable notifications for Ruby &amp; Rails — <b>Zalo first</b>.<br>
  Idempotency, safe retries and a transactional outbox, on <i>your</i> infrastructure.
</p>

<p align="center">
  <a href="https://github.com/vochihieu8320/notifykit/actions/workflows/ci.yml"><img src="https://github.com/vochihieu8320/notifykit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/ruby-%E2%89%A5%203.2-red" alt="Ruby >= 3.2">
  <img src="https://img.shields.io/badge/rails-%E2%89%A5%207.0-red" alt="Rails >= 7.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT"></a>
</p>

> **Status:** early development (v0.1, not yet on RubyGems). APIs may change.
> Not related to the unmaintained [`notifykit`](https://rubygems.org/gems/notifykit) gem from 2014 —
> this gem is published as **`notify_kit`**.

---

## Why

Sending a Zalo ZNS message is one HTTP call. Sending it **reliably** is not:

- a retried job or a double-clicked button sends the customer **two** OTPs;
- the order commits but the process dies before the job is enqueued — the customer gets **nothing**;
- Zalo times out: did it deliver or not? Retrying blindly may **duplicate**, not retrying may **lose** it;
- Zalo refresh tokens are **single-use** — two workers refreshing at once lock you out of your OA.

NotifyKit handles these once, behind one API, using the database and job queue your app already has.
No extra service to run, no data sent anywhere except to the provider.

## Features

- **Idempotency** — one logical message per idempotency key, enforced by a unique index;
  reusing a key with a different payload is rejected.
- **Transactional outbox** — the message is written in *your* ActiveRecord transaction:
  it exists if and only if your business data commits.
- **Safe retries** — explicit error taxonomy; exponential backoff with jitter; `Retry-After` honoured;
  ambiguous failures are **never** retried blindly.
- **Crash recovery** — leased work items with `SKIP LOCKED`; a dead worker's message is picked up again,
  and NotifyKit knows whether the provider may already have received it.
- **Zalo built in** — ZNS/ZBS template messages (to a phone number) and OA messages (to a user id),
  Vietnamese phone normalisation, Zalo error mapping, race-safe token refresh.
- **Pluggable** — storage, dispatcher, token store and providers are adapters. Core has **one** runtime
  dependency (`zeitwerk`) and does not load Rails.

## Guarantees (and non-guarantees)

| Setup | What you get |
|---|---|
| `Storage::Memory` (default) | Best effort, in-process. Dedup within the process. Nothing survives a restart. |
| `ActiveRecordStorage` | At most one logical message per `(namespace, idempotency_key)`; persisted iff your transaction commits; each due message processed by one worker at a time; crashed workers recovered after the lease expires. |
| Provider timeout after sending | State `unknown_outcome` — **not** resent unless the provider de-duplicates. Zalo does not, so NotifyKit sends our message id as `tracking_id` for reconciliation. |

NotifyKit does **not** promise exactly-once *physical* delivery — no client library can when the
provider has no idempotency key. It makes the ambiguous cases explicit instead of hiding them.

## Installation

```ruby
# Gemfile
gem "notify_kit", github: "vochihieu8320/notifykit"
```

## Quick start (no database)

```ruby
require "notify_kit"

NotifyKit.configure do |c|
  c.provider :shop_zalo, :zalo_zns,
             app_id: ENV.fetch("ZALO_APP_ID"),
             app_secret: ENV.fetch("ZALO_APP_SECRET"),
             token_store: NotifyKit::TokenStores::Memory.new(
               "shop_zalo" => NotifyKit::Token.new(access_token: ENV.fetch("ZALO_ACCESS_TOKEN"),
                                                   refresh_token: ENV.fetch("ZALO_REFRESH_TOKEN"))
             )
end

result = NotifyKit.deliver(
  to: "0912 345 678",              # normalised to 84912345678
  template: "231802",              # approved ZNS template id
  data: { customer_name: "An", order_code: "A1" },
  idempotency_key: "order:A1:paid"
)

result.success?          # => true
result[:duplicate]       # => true when this key was already requested
NotifyKit.status(result[:message_id]).state   # => "accepted"
```

## Rails (durable mode)

```sh
bundle add notify_kit --github vochihieu8320/notifykit
bin/rails g notify_kit:install   # migration + config/initializers/notify_kit.rb
bin/rails db:migrate
```

The generated initializer uses your database and your ActiveJob backend:

```ruby
NotifyKit.configure do |c|
  c.storage    = NotifyKit::Storage::ActiveRecordStorage.new
  c.dispatcher = NotifyKit::Dispatchers::ActiveJobDispatcher.new
  c.provider :zalo, :zalo_zns,
             app_id: ENV.fetch("ZALO_APP_ID", nil),
             app_secret: ENV.fetch("ZALO_APP_SECRET", nil),
             token_store: NotifyKit::TokenStores::ActiveRecordStore.new
  c.retry_policy = NotifyKit::RetryPolicy.new(max_attempts: 5)
end
```

Send inside the same transaction as your business change:

```ruby
ActiveRecord::Base.transaction do
  order.update!(status: :paid)
  NotifyKit.deliver(to: order.phone, template: "231802",
                    data: { order_code: order.code },
                    idempotency_key: "order:#{order.id}:paid")
end
# rolled back => no message. committed => a DispatchJob is enqueued after commit.
```

Run the poller so retries happen and lost jobs are recovered:

```sh
bin/rails notify_kit:work            # or schedule `NotifyKit.dispatch_due` as a recurring job
```

### Zalo tokens

Obtain the first OA access/refresh token with Zalo's OAuth v4 flow, then store it once:

```ruby
NotifyKit::TokenStores::ActiveRecordStore.new.save(
  :zalo, NotifyKit::Token.new(access_token: "...", refresh_token: "...", expires_at: 25.hours.from_now)
)
```

NotifyKit refreshes it before expiry and on `-216`/`-220` errors, under a row lock so concurrent
workers never burn the single-use refresh token. Consider encrypting the columns:
`NotifyKit::Records::ProviderToken.encrypts :access_token, :refresh_token`.

## Error taxonomy

Providers translate vendor responses into one of these; retry decisions use only the class.

| Error | Meaning | Retried? |
|---|---|---|
| `RateLimited` | provider throttled (`retry_after` honoured) | yes |
| `TransientFailure` | request provably not processed (connect error, 502/503/504) | yes |
| `UnknownOutcome` | request may have been processed (read timeout, 500) | only if the provider de-duplicates |
| `AuthFailure` | credentials/token rejected (Zalo tokens refreshed once automatically) | no |
| `InvalidRecipient`, `InvalidTemplate`, `NotEligible`, `PermanentFailure` | cannot succeed | no |
| `IdempotencyConflict` | same key, different payload | — (nothing sent) |

Unknown Zalo error codes map to `PermanentFailure`. Map more once verified:
`c.provider :zalo, :zalo_zns, ..., error_codes: { -1234 => :rate_limited }`.

## Adding a provider

1. Subclass `NotifyKit::Providers::Base`: declare `capabilities`, implement `validate!` (no I/O)
   and `deliver`, raising only NotifyKit errors.
2. Register it: `NotifyKit::Providers::Registry.register(:my_sms, MySms)`.
3. Prove it with the shared contract: `it_behaves_like "a NotifyKit provider"`.

No change to the core is needed — see [`docs/architecture.md`](docs/architecture.md).

## Development

Everything runs in Docker (Ruby 3.3 + PostgreSQL 16):

```sh
docker compose run --rm app bundle install
bin/dev bundle exec rspec      # unit, provider conformance and integration specs on Postgres
bin/dev bundle exec rubocop
```

Specs use a real mock Zalo HTTP server — never real credentials.

## Roadmap

- [x] Core: idempotency, retry policy, outbox dispatch, crash recovery
- [x] Zalo ZNS / OA provider with race-safe token refresh
- [x] Rails: ActiveRecord storage, ActiveJob dispatcher, install generator
- [ ] Instrumentation (`ActiveSupport::Notifications`), log redaction, reconciliation hooks
- [ ] Demo Rails app with failure-injection script
- [ ] SMS fallback provider, email provider

## License

[MIT](LICENSE)
