# frozen_string_literal: true

RSpec.describe NotifyKit::Storage::Memory do
  it_behaves_like "a NotifyKit storage adapter" do
    let(:storage) { described_class.new }
  end

  it "creates exactly one message for 100 concurrent requests with the same key" do
    storage = described_class.new
    msg = NotifyKit::Message.new(provider: :fake, to: "0912345678", template: "t", idempotency_key: "same")
    threads = Array.new(100) { Thread.new { storage.enqueue(msg, available_at: Time.now) } }
    results = threads.map(&:value)
    expect([results.count { |_, created| created }, results.map { |m, _| m.id }.uniq.size]).to eq([1, 1])
  end
end
