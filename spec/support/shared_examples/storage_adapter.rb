# frozen_string_literal: true

# The storage contract (see NotifyKit::Ports::Storage). Run against every adapter.
# Required let: storage
RSpec.shared_examples "a NotifyKit storage adapter" do
  let(:now) { Time.utc(2026, 11, 8, 9, 0, 0) }

  def message(key: "k-1", data: { "order" => "A1" })
    NotifyKit::Message.new(provider: :fake, to: "0912345678", template: "t1", data:, idempotency_key: key)
  end

  describe "#enqueue" do
    it "creates a queued message" do
      stored, created = storage.enqueue(message, available_at: now)
      aggregate_failures do
        expect(created).to be(true)
        expect(stored.state).to eq("queued")
        expect(storage.find(stored.id).fingerprint).to eq(message.fingerprint)
      end
    end

    it "returns the existing message for the same key and payload" do
      first, = storage.enqueue(message, available_at: now)
      second, created = storage.enqueue(message, available_at: now)
      expect([second.id, created]).to eq([first.id, false])
    end

    it "raises IdempotencyConflict for the same key with another payload" do
      storage.enqueue(message, available_at: now)
      expect { storage.enqueue(message(data: { "order" => "B2" }), available_at: now) }
        .to raise_error(NotifyKit::IdempotencyConflict)
    end

    it "allows many messages without an idempotency key" do
      ids = Array.new(2) { storage.enqueue(message(key: nil), available_at: now).first.id }
      expect(ids.uniq.size).to eq(2)
    end

    it "calls on_commit only when a row is created" do
      calls = []
      2.times { storage.enqueue(message, available_at: now, on_commit: ->(id) { calls << id }) }
      expect(calls.size).to eq(1)
    end
  end

  describe "#claim" do
    it "claims due messages once" do
      stored, = storage.enqueue(message, available_at: now)
      first = storage.claim(worker_id: "w1", now:, lease_seconds: 60, limit: 10)
      second = storage.claim(worker_id: "w2", now:, lease_seconds: 60, limit: 10)
      expect([first.map(&:id), second]).to eq([[stored.id], []])
    end

    it "does not claim messages scheduled in the future" do
      storage.enqueue(message, available_at: now + 30)
      expect(storage.claim(worker_id: "w1", now:, lease_seconds: 60, limit: 10)).to be_empty
    end

    it "reclaims a message whose lease expired" do
      stored, = storage.enqueue(message, available_at: now)
      storage.claim(worker_id: "w1", now:, lease_seconds: 60, limit: 10)
      reclaimed = storage.claim(worker_id: "w2", now: now + 61, lease_seconds: 60, limit: 10)
      expect(reclaimed.map { |m| [m.id, m.locked_by] }).to eq([[stored.id, "w2"]])
    end

    it "filters by ids" do
      a, = storage.enqueue(message(key: "a"), available_at: now)
      storage.enqueue(message(key: "b"), available_at: now)
      expect(storage.claim(worker_id: "w1", now:, lease_seconds: 60, limit: 10, ids: [a.id]).map(&:id)).to eq([a.id])
    end
  end

  describe "attempts and release" do
    let!(:stored) { storage.enqueue(message, available_at: now).first }

    before { storage.claim(worker_id: "w1", now:, lease_seconds: 60, limit: 10) }

    it "numbers attempts and tracks the in-flight one" do
      attempt = storage.start_attempt(message_id: stored.id, provider: :fake, now:)
      aggregate_failures do
        expect(attempt.number).to eq(1)
        expect(storage.unfinished_attempt(stored.id)&.id).to eq(attempt.id)
      end
    end

    it "finishes an attempt" do
      attempt = storage.start_attempt(message_id: stored.id, provider: :fake, now:)
      storage.finish_attempt(attempt.id, outcome: :accepted, now:, provider_message_id: "p-1")
      expect(storage.attempts(stored.id).map { |a| [a.outcome, a.provider_message_id] }).to eq([%w[accepted p-1]])
    end

    it "releases only for the lease holder" do
      aggregate_failures do
        expect(storage.release(stored.id, worker_id: "intruder", state: "accepted", now:)).to be(false)
        expect(storage.release(stored.id, worker_id: "w1", state: "accepted", now:)).to be(true)
        expect(storage.find(stored.id).state).to eq("accepted")
      end
    end

    it "records the error category on release" do
      storage.release(stored.id, worker_id: "w1", state: "failed", now:,
                                 error: NotifyKit::InvalidRecipient.new("nope"))
      expect(storage.find(stored.id).last_error_category).to eq("invalid_recipient")
    end
  end
end
