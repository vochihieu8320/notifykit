# frozen_string_literal: true

RSpec.describe NotifyKit::Client do
  subject(:client) { described_class.new(config) }

  let(:clock) { TestClock.new }
  let(:outcomes) { [] }
  let(:idempotent_send) { false }
  let(:config) do
    NotifyKit::Configuration.new.tap do |c|
      c.clock = clock
      c.retry_policy = NotifyKit::RetryPolicy.new(max_attempts: 3, random: Random.new(1))
      c.provider :test, :fake, outcomes:, idempotent_send:, invalid_recipients: ["blocked"]
    end
  end
  let(:fake) { client.providers.fetch(:test) }

  def deliver(**overrides)
    client.deliver(to: "0912345678", template: "t1", data: { order: "A1" }, idempotency_key: "order:1", **overrides)
  end

  describe "#deliver" do
    context "when the provider accepts" do
      it "persists and sends the message once" do
        result = deliver
        aggregate_failures do
          expect(result).to be_success
          expect(client.status(result[:message_id]).state).to eq("accepted")
          expect(fake.received.size).to eq(1)
        end
      end
    end

    context "when the same request is repeated" do
      it "returns the original message without sending again" do
        first = deliver
        second = deliver
        aggregate_failures do
          expect(second[:message_id]).to eq(first[:message_id])
          expect(second[:duplicate]).to be(true)
          expect(fake.received.size).to eq(1)
        end
      end
    end

    context "when the key is reused with a different payload" do
      it "fails with IdempotencyConflict and sends nothing new" do
        deliver
        result = deliver(data: { order: "B2" })
        expect([result.error.class, fake.received.size]).to eq([NotifyKit::IdempotencyConflict, 1])
      end
    end

    context "when the recipient is invalid" do
      it "fails before persisting" do
        result = deliver(to: "blocked")
        expect([result.error.class, result[:message_id]]).to eq([NotifyKit::InvalidRecipient, nil])
      end
    end

    context "when the provider is rate limited" do
      let(:outcomes) { [NotifyKit::RateLimited.new("slow down", retry_after: 30)] }

      it "schedules a retry no earlier than Retry-After" do
        stored = client.status(deliver[:message_id])
        expect([stored.state, stored.available_at]).to eq(["retry_scheduled", clock.now + 30])
      end

      it "delivers on the next due dispatch" do
        id = deliver[:message_id]
        clock.advance(31)
        client.dispatch_due
        expect([client.status(id).state, client.attempts(id).map(&:outcome)]).to eq(["accepted", %w[failed accepted]])
      end
    end

    context "when the response is lost and the provider cannot de-duplicate" do
      let(:outcomes) { [NotifyKit::UnknownOutcome.new("read timeout")] }

      it "stops in unknown_outcome instead of resending" do
        id = deliver[:message_id]
        clock.advance(3600)
        client.dispatch_due
        expect([client.status(id).state, fake.received.size]).to eq(["unknown_outcome", 1])
      end
    end

    context "when the response is lost but the provider de-duplicates" do
      let(:outcomes) { [NotifyKit::UnknownOutcome.new("read timeout")] }
      let(:idempotent_send) { true }

      it "retries" do
        id = deliver[:message_id]
        clock.advance(3600)
        client.dispatch_due
        expect(client.status(id).state).to eq("accepted")
      end
    end

    context "when failures exhaust max_attempts" do
      let(:outcomes) { Array.new(3) { NotifyKit::TransientFailure.new("502") } }

      it "ends failed after 3 attempts" do
        id = deliver[:message_id]
        2.times do
          clock.advance(3600)
          client.dispatch_due
        end
        expect([client.status(id).state, client.attempts(id).size]).to eq(["failed", 3])
      end
    end
  end

  describe "worker crash recovery" do
    let(:config) do
      super().tap { |c| c.dispatcher = ->(_client, _id) {} } # no inline kick: we drive dispatch by hand
    end
    let(:storage) { config.storage }

    it "resends when the worker died before calling the provider" do
      id = deliver[:message_id]
      storage.claim(worker_id: "dead-worker", now: clock.now, lease_seconds: 60, limit: 1)
      clock.advance(61)
      client.dispatch_due
      expect([client.status(id).state, fake.received.size]).to eq(["accepted", 1])
    end

    it "does not resend when the worker died during the provider call" do
      id = deliver[:message_id]
      storage.claim(worker_id: "dead-worker", now: clock.now, lease_seconds: 60, limit: 1)
      storage.start_attempt(message_id: id, provider: :test, now: clock.now)
      clock.advance(61)
      client.dispatch_due
      expect([client.status(id).state, fake.received.size]).to eq(["unknown_outcome", 0])
    end
  end
end
