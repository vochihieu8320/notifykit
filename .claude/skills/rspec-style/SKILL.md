---
name: rspec-style
description: How to write RSpec specs in NotifyKit — service specs, provider conformance shared examples, mock HTTP servers, concurrency/idempotency specs. Use whenever adding or changing specs, or adding a feature/provider (every behavior change needs a spec).
---

# RSpec style (NotifyKit)

RSpec only (no Minitest). Every behavior change ships with a spec; write the failing spec first
when practical and show the real failure before implementing.

## Layout

```
spec/
├── notify_kit/                 # unit specs mirror lib/notify_kit/
│   ├── services/…_spec.rb
│   ├── providers/zalo/…_spec.rb
│   └── storage/…_spec.rb
├── integration/                # real DB (spec/dummy) + mock provider servers
├── conformance/                # shared examples run against EVERY provider/adapter
├── support/
│   ├── shared_examples/provider.rb
│   ├── shared_examples/storage_adapter.rb
│   └── mock_servers/zalo.rb    # Rack app; modes: ok, timeout, 429, expired_token, ...
└── dummy/                      # minimal Rails 7 app for integration specs
```

## Service spec template

```ruby
# frozen_string_literal: true

RSpec.describe NotifyKit::Messages::Deliver do
  describe ".call" do
    subject(:result) { described_class.call(message:, provider:) }

    let(:message)  { build(:message, channel: :zalo_zns) }
    let(:provider) { instance_double(NotifyKit::Providers::Zalo::Zns) }

    context "when the provider accepts the message" do
      before { allow(provider).to receive(:deliver).and_return(accepted_response) }

      it "returns a success result" do
        expect(result).to be_success
      end
    end

    context "when the provider times out after sending" do
      before { allow(provider).to receive(:deliver).and_raise(NotifyKit::UnknownOutcome) }

      it "marks the message unknown_outcome without retrying" do
        aggregate_failures do
          expect(result).to be_failure
          expect(message.reload.state).to eq("unknown_outcome")
        end
      end
    end
  end
end
```

Rules:
- `describe ".call"` / `describe "#method"`; `context "when …"`; `it` in present tense, no
  "should", no "and" (split into two examples or use `aggregate_failures`).
- `subject(:result)` named; `let` by default, `let!` only when the record must pre-exist.
- `instance_double` / `class_double` for collaborators — never plain `double`.
- Do not mock ActiveRecord; use the dummy DB.
- Stub HTTP at the boundary: mock Rack servers in `spec/support/mock_servers` (or WebMock if
  added later). Never hit real Zalo/SMS APIs in the default suite; real calls live behind
  `REAL_PROVIDERS=1` and are skipped in CI.
- Time: `travel_to` / injected clock, never `sleep`.

## Conformance (the scaling mechanism)

Every provider runs the same shared examples, so adding a provider = adding a spec file:

```ruby
RSpec.describe NotifyKit::Providers::Zalo::Zns do
  it_behaves_like "a NotifyKit provider",
                  mock_server: MockServers::Zalo,
                  valid_message: -> { build(:message, :zalo_zns) }
end
```

`spec/support/shared_examples/provider.rb` must cover: declares capabilities; validates before
sending; maps 429 → `RateLimited` (with retry_after); maps auth errors → `AuthFailure`; maps a
timeout after the request was sent → `UnknownOutcome`; never raises raw HTTP/JSON errors;
redacts secrets from errors and logs. Same idea for `"a NotifyKit storage adapter"`.

## Must-have reliability specs

- 100 threads, same idempotency key, same payload → exactly 1 message row (use
  `Thread.new` + a barrier, real DB, `use_transactional_fixtures = false` for that file).
- Same key, different payload → `IdempotencyConflict`.
- Business transaction rolled back → no outbox row.
- Worker lease expires → another worker picks the message up.
- Concurrent token refresh → refresh endpoint called once.

## Running

`bundle exec rspec` (all), `bundle exec rspec spec/conformance` (provider contract).
Report the real command output; do not claim green without running it.
