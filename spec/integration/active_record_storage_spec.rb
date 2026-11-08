# frozen_string_literal: true

require "active_record_helper"

RSpec.describe NotifyKit::Storage::ActiveRecordStorage, :db do
  it_behaves_like "a NotifyKit storage adapter" do
    let(:storage) { described_class.new }
  end

  context "when 100 requests with the same idempotency key race" do
    it "persists exactly one message" do
      storage = described_class.new
      msg = NotifyKit::Message.new(provider: :fake, to: "0912345678", template: "t", idempotency_key: "order:1")
      results = in_threads(100) { storage.enqueue(msg, available_at: Time.now.utc) }
      aggregate_failures do
        expect(NotifyKit::Records::Message.count).to eq(1)
        expect(results.count { |_, created| created }).to eq(1)
        expect(results.map { |m, _| m.id }.uniq.size).to eq(1)
      end
    end
  end

  context "when two workers claim at the same time" do
    it "gives every message to exactly one worker" do
      storage = described_class.new
      20.times do |i|
        storage.enqueue(NotifyKit::Message.new(provider: :fake, to: "x", idempotency_key: "k#{i}"),
                        available_at: Time.now.utc)
      end
      claimed = in_threads(4) do |i|
        storage.claim(worker_id: "w#{i}", now: Time.now.utc, lease_seconds: 60, limit: 20).map(&:id)
      end
      expect(claimed.flatten.sort).to eq(NotifyKit::Records::Message.order(:id).pluck(:id))
    end
  end

  context "when called inside a transaction that hits a duplicate key" do
    it "keeps the caller's transaction usable" do
      storage = described_class.new
      msg = NotifyKit::Message.new(provider: :fake, to: "x", idempotency_key: "dup")
      storage.enqueue(msg, available_at: Time.now.utc)
      ActiveRecord::Base.transaction do
        storage.enqueue(msg, available_at: Time.now.utc)
        Order.create!(code: "after-duplicate")
      end
      expect(Order.pluck(:code)).to eq(["after-duplicate"])
    end
  end
end
