# NotifyKit — Gem architecture (draft v0.1)

Goal: a Ruby SDK that sends notifications reliably (dedup, safe retry, outbox) on the host
app's own infrastructure, where **Zalo is the first of many providers**. Adding provider #2…#N
must not touch the core.

## 1. Prior art — how well-known multi-provider Ruby gems scale

| Gem | Pattern worth copying | What we take |
|---|---|---|
| **ActiveStorage** (`Service::S3Service`, `GCSService`, …) | Abstract service class + one subclass per vendor, selected by config key | Provider base class + registry keyed by symbol |
| **ActionMailer delivery methods** | `add_delivery_method :name, Klass, settings` | Register providers at runtime, settings per key |
| **OmniAuth** (`omniauth-google`, `omniauth-facebook`) | Core gem + one gem per strategy | Path to split `notify_kit-zalo`, `notify_kit-esms` later |
| **Pay** (Stripe / Braintree / Paddle) | `lib/pay/<processor>/` folder per vendor, shared models, processor chosen per record | Folder per vendor; storage records store `provider_key` |
| **ActiveMerchant** (100+ gateways) | Tiny uniform interface (`purchase`, `refund`) + `Response` object, vendor quirks hidden in gateway | `deliver` → `ProviderResponse`; error mapping inside provider |
| **Noticed** | Notification → many delivery methods (email, SMS, Slack) | Channel fallback/routing (ZNS → SMS) as policy, not inside a provider |
| **Faraday** | Adapter (transport) + middleware stack | `HttpTransport` port; retry/instrumentation as wrappers |

Common lesson: **core knows interfaces; vendors know quirks.** Vendor code is isolated in its
own folder (later its own gem) and verified by a shared contract test suite.

## 2. Core concepts (vocabulary)

| Term | Meaning | Example |
|---|---|---|
| **Channel** | Medium the recipient sees | `:zalo`, `:sms`, `:email` |
| **Provider type** | Class implementing a vendor API for a channel | `Zalo::Zns`, `Zalo::OaMessage`, `Esms::Sms` |
| **Provider instance** | A configured account of a type (name + credentials) | `:shop_a_zalo` = Zns with OA #1, `:shop_b_zalo` = Zns with OA #2 |
| **Message** | Immutable value: channel, recipient, template/content, idempotency key | `Message.new(channel: :zalo, to: "0987…", template: "order_confirmed", data: {...})` |
| **Delivery attempt** | One physical call to a provider | attempt #2 to `:shop_a_zalo` |
| **Route** | Ordered list of provider instances + fallback policy | `[:shop_a_zalo, :esms_main]`, fallback only on `NotEligible`/`InvalidRecipient` |

Separating *type* from *instance* is what makes multi-tenant (many OAs) and multi-provider work
without `if provider == :zalo` anywhere.

## 3. Layers

```
┌──────────────────────────────────────────────────────────────┐
│ Public API   NotifyKit.configure, NotifyKit::Client#deliver,  │
│              #status, #attempts                               │
├──────────────────────────────────────────────────────────────┤
│ Services     Messages::Enqueue  (idempotency + outbox write)  │
│              Outbox::Dispatch   (claim with lease → Deliver)  │
│              Messages::Deliver  (route → provider → record)   │
│              RetryPolicy, Messages::Reconcile                 │
├──────────────────────────────────────────────────────────────┤
│ Ports        Storage · Dispatcher · TokenStore · HttpTransport│
│              Clock · Instrumenter · Lock                      │
├───────────────────────┬──────────────────────────────────────┤
│ Adapters              │ Providers (registry)                 │
│ storage/memory        │ zalo/zns, zalo/oa_message            │
│ storage/active_record │ esms/sms   (later)                   │
│ dispatchers/inline    │ ses/email  (later)                   │
│ dispatchers/active_job│ test/fake  (for host-app tests)      │
├───────────────────────┴──────────────────────────────────────┤
│ Rails glue (optional) Railtie · install generator · AR models │
│                       · ActiveJob job · ErrorHandler concern │
└──────────────────────────────────────────────────────────────┘
```

Dependency rule: arrows point down only. Services depend on ports + registry, never on a
concrete adapter/provider. Core loads without Rails.

## 4. Directory layout

```
notify_kit/
├── lib/
│   ├── notify_kit.rb                  # Zeitwerk loader, configure, top-level API
│   └── notify_kit/
│       ├── version.rb
│       ├── configuration.rb
│       ├── client.rb                  # public API object (thin)
│       ├── errors.rb                  # NotifyKit::Error hierarchy (taxonomy)
│       ├── message.rb  result.rb  provider_response.rb  capabilities.rb   # value objects
│       ├── services/
│       │   ├── messages/{enqueue,deliver,reconcile}.rb
│       │   ├── outbox/dispatch.rb
│       │   └── retry_policy.rb
│       ├── ports/                     # contracts (docs + NotImplementedError base modules)
│       ├── storage/{memory,active_record}.rb
│       ├── dispatchers/{inline,active_job}.rb
│       ├── token_stores/{memory,active_record}.rb
│       ├── transports/net_http.rb
│       ├── providers/
│       │   ├── base.rb  registry.rb
│       │   ├── fake/                  # deterministic provider for host-app tests
│       │   └── zalo/{zns,oa_message,client,error_mapper,token_manager}.rb
│       ├── support/{vn_phone,redactor,retry_after,backoff}.rb
│       └── rails/
│           ├── railtie.rb
│           ├── error_handler.rb       # rescue_from mapping for host controllers
│           ├── models/{message,delivery_attempt,outbox_entry,provider_token}.rb
│           ├── models/concerns/{idempotent,leasable,state_machine}.rb
│           ├── jobs/dispatch_job.rb
│           └── generators/notify_kit/install/{install_generator.rb,templates/*.rb.tt}
├── spec/  (see rspec-style skill)
│   └── dummy/                         # Rails 7 app, Postgres in docker-compose
├── examples/rails_demo/               # demo Rails app (thin controllers + services)
├── docs/{architecture.md, adr/}
└── notify_kit.gemspec
```

Naming: gem `notify_kit` ↔ module `NotifyKit` (Ruby convention: underscore ↔ CamelCase).

## 5. Key flows

**Enqueue (inside the caller's transaction)**
```ruby
ActiveRecord::Base.transaction do
  order.update!(status: :paid)
  NotifyKit.deliver(to: order.phone, template: :order_paid, data: {...},
                    idempotency_key: "order:#{order.id}:paid", route: :default)
end # message + outbox row commit atomically with the order
```
`Messages::Enqueue`: fingerprint payload → `INSERT … ON CONFLICT (namespace, idempotency_key) DO NOTHING`
→ existing row with same fingerprint returns its id; different fingerprint → `IdempotencyConflict`.

**Dispatch (worker)**: `Outbox::Dispatch` claims due rows `FOR UPDATE SKIP LOCKED` with a
lease → `Messages::Deliver` → provider → record attempt → transition state / schedule retry.
Dispatcher port decides *how* it runs: inline loop, ActiveJob (Sidekiq/GoodJob/SolidQueue
underneath), or a cron poller.

**Retry decision** (`RetryPolicy`, provider-agnostic): driven only by error class +
`capabilities.idempotent_send?`. `UnknownOutcome` is never blindly retried; route fallback only
on errors that prove the first provider did *not* deliver.

## 6. Scaling plan

1. **Now**: mono-gem, providers in `lib/notify_kit/providers/<vendor>/`, conformance suite.
2. **When a 2nd/3rd provider is stable**: extract `notify_kit-zalo`, `notify_kit-esms` gems
   (OmniAuth model). Core keeps `fake` provider only. Registry already makes this a no-op for
   users except the Gemfile line.
3. **Ecosystem**: third parties write providers by subclassing `Base` and running the
   published shared examples (`require "notify_kit/rspec"`).

## 7. Open questions (decide before coding)

- Ruby minimum (proposal: 3.2, enables `Data.define`) and Rails range (proposal: `>= 7.0`).
- Zeitwerk as the only runtime dependency? (proposal: yes)
- Template rendering for email: later, not in v0.1.
- Docs/commit language.
