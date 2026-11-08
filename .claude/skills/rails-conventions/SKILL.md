---
name: rails-conventions
description: NotifyKit's Ruby/Rails code conventions — thin controllers, shared ErrorHandler module, business logic in service objects, models split with concerns. Use whenever writing or reviewing Ruby/Rails code in this repo (gem code, spec/dummy app, examples/ demo app).
---

# Rails conventions (NotifyKit)

These rules are the project's own choices. When an external guide (e.g. thoughtbot "PORO over
service objects", 37signals "fat models") disagrees, **these rules win**.

## Layer responsibilities

| Layer | Allowed | Not allowed |
|---|---|---|
| Controller | parse params (strong params), call ONE service, render result / status | business rules, queries beyond a `find`, `rescue` blocks, provider calls |
| Service (`app/services`, gem: `lib/notify_kit/services`) | business logic, orchestration, transactions | rendering, reading `params`/`request` directly |
| Model | associations, validations, scopes, small value helpers | HTTP calls, multi-model orchestration, callbacks with side effects (no `after_save :send_x`) |
| Concern (`app/models/concerns`) | one cohesive behavior shared by ≥1 model (e.g. `Idempotent`, `Leasable`) | dumping-ground modules, concerns that depend on a specific host class |
| ErrorHandler | maps exceptions → HTTP responses in ONE place | — |

## Service objects

```ruby
module Messages
  class Deliver
    def self.call(...) = new(...).call

    def initialize(message:, provider:)
      @message = message
      @provider = provider
    end

    def call
      # ...
      Result.success(message_id: @message.id)
    end
  end
end
```

- One public entry point: `.call` (class) → `#call` (instance). Everything else `private`.
- Name = verb + noun, namespaced by domain: `Messages::Deliver`, `Outbox::Dispatch`, `Tokens::Refresh`.
- Return a `Result` object (success?/failure?, value, error). Raise only for programmer errors
  or for errors the ErrorHandler is meant to map.
- Inject collaborators via keyword args with sensible defaults → easy to stub in specs.
- Wrap multi-write operations in a transaction inside the service, not in the controller.

## Error handling

- All gem errors inherit from `NotifyKit::Error` (see `lib/notify_kit/errors.rb`); categories are
  subclasses (`RateLimited`, `AuthFailure`, `InvalidRecipient`, `InvalidTemplate`,
  `TransientFailure`, `UnknownOutcome`, `PermanentFailure`, `NotEligible`, `IdempotencyConflict`).
- Rails apps: a single `ErrorHandler` module (outside `app/`, e.g. `lib/error_handler.rb` or the
  gem's `NotifyKit::Rails::ErrorHandler`) declares every `rescue_from`. Controllers only
  `include ErrorHandler`. No `begin/rescue` inside controller actions.
- Never rescue `Exception`; rescue the narrowest class. Never swallow an error silently — log it
  with structured fields.

## Models & concerns

```ruby
class NotifyKit::Message < ApplicationRecord
  include NotifyKit::Idempotent   # concern: unique key + payload fingerprint
  include NotifyKit::StateMachine # concern: allowed transitions only

  has_many :delivery_attempts
  validates :channel, :recipient, presence: true
  scope :due, -> { where(state: "queued").where("available_at <= ?", Time.current) }
end
```

- Concern file holds `extend ActiveSupport::Concern`, its `included do` block, and the methods
  for that single behavior. Name concerns as adjectives/capabilities.
- Host-app model names are configurable strings, never hard-coded constants (`::User`).

## General Ruby

- `# frozen_string_literal: true` at top of every file.
- Keyword arguments for anything with >1 parameter.
- Comments explain **why**, not what. `TODO` must say what + why (`# TODO(zalo): switch to ZBS endpoint once ...`).
- Structured logging: one hash per log line, `event:` key first, never log tokens/phone numbers in
  clear (use `NotifyKit::Redactor`).
- No new gem dependency without asking the user first.
- Lint: follow the repo's RuboCop config; style questions defer to it.
