# frozen_string_literal: true

RSpec.describe NotifyKit::RetryPolicy do
  subject(:policy) { described_class.new(max_attempts: 3, base_delay: 2.0, max_delay: 60.0, random:) }

  let(:random) { instance_double(Random, rand: 0.5) }
  let(:now) { Time.utc(2026, 11, 8) }
  let(:plain) { NotifyKit::Capabilities.new(channel: :zalo, recipient_kind: :phone) }
  let(:idempotent) { NotifyKit::Capabilities.new(channel: :x, recipient_kind: :any, idempotent_send: true) }

  def decide(error, attempt: 1, capabilities: plain)
    policy.decide(error:, attempt_number: attempt, capabilities:, now:)
  end

  describe "#decide" do
    it "retries a transient failure with backoff" do
      decision = decide(NotifyKit::TransientFailure.new("502"))
      expect([decision.action, decision.at]).to eq([:retry, now + 1.5])
    end

    it "honours Retry-After when it is longer than the backoff" do
      expect(decide(NotifyKit::RateLimited.new("429", retry_after: 30)).at).to eq(now + 30)
    end

    it "stops in unknown when the provider cannot de-duplicate" do
      expect(decide(NotifyKit::UnknownOutcome.new("timeout")).action).to eq(:unknown)
    end

    it "retries an unknown outcome when the provider is idempotent" do
      expect(decide(NotifyKit::UnknownOutcome.new("timeout"), capabilities: idempotent).action).to eq(:retry)
    end

    it "fails permanent errors immediately" do
      expect(decide(NotifyKit::InvalidRecipient.new("bad")).action).to eq(:fail)
    end

    it "fails when attempts are exhausted" do
      expect(decide(NotifyKit::TransientFailure.new("502"), attempt: 3).action).to eq(:fail)
    end
  end

  describe "#delay" do
    it "grows exponentially and is capped" do
      expect([1, 2, 3, 10].map { |n| policy.delay(n) }).to eq([1.5, 3.0, 6.0, 45.0])
    end
  end
end
