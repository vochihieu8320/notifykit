# frozen_string_literal: true

require "active_record_helper"

# End-to-end durable mode: ActiveRecord storage + ActiveJob dispatcher, as a host
# Rails app would configure it.
RSpec.describe "Transactional outbox", :db do
  let(:clock) { TestClock.new(Time.now.utc) }
  let(:fake) { NotifyKit.client.providers.fetch(:test) }
  let(:enqueued) { ActiveJob::Base.queue_adapter.enqueued_jobs }

  before do
    NotifyKit.configure do |c|
      c.storage = NotifyKit::Storage::ActiveRecordStorage.new
      c.dispatcher = NotifyKit::Dispatchers::ActiveJobDispatcher.new
      c.clock = clock
      c.provider :test, :fake
    end
  end

  def pay_order(code)
    ActiveRecord::Base.transaction do
      order = Order.create!(code:, status: "paid")
      NotifyKit.deliver(to: "0912345678", template: "order_paid", data: { code: }, idempotency_key: "order:#{code}")
      yield order if block_given?
    end
  end

  context "when the business transaction rolls back" do
    it "leaves no message and enqueues no job" do
      pay_order("A1") { raise ActiveRecord::Rollback }
      expect([Order.count, NotifyKit::Records::Message.count, enqueued.size]).to eq([0, 0, 0])
    end
  end

  context "when the business transaction commits" do
    it "enqueues the dispatch job only after commit" do
      pay_order("A1") { expect(enqueued).to be_empty }
      expect(enqueued.map { |j| j["job_class"] }).to eq(["NotifyKit::DispatchJob"])
    end

    it "delivers when the job runs" do
      pay_order("A1")
      NotifyKit::DispatchJob.perform_now(*enqueued.first["arguments"])
      expect([NotifyKit::Records::Message.last.state, fake.received.size]).to eq(["accepted", 1])
    end

    it "delivers once even if the job runs twice" do
      pay_order("A1")
      2.times { NotifyKit::DispatchJob.perform_now(*enqueued.first["arguments"]) }
      expect(fake.received.size).to eq(1)
    end
  end

  context "when the job is lost after commit" do
    it "is still delivered by the poller" do
      pay_order("A1")
      enqueued.clear # Redis down / process killed right after commit
      NotifyKit.dispatch_due
      expect(NotifyKit::Records::Message.last.state).to eq("accepted")
    end
  end

  context "when the worker dies mid-request" do
    it "marks the message unknown_outcome instead of resending" do
      pay_order("A1")
      storage = NotifyKit.configuration.storage
      id = NotifyKit::Records::Message.last.id
      storage.claim(worker_id: "dead", now: clock.call, lease_seconds: 60, limit: 1)
      storage.start_attempt(message_id: id, provider: :test, now: clock.call)
      clock.advance(61)
      NotifyKit.dispatch_due
      expect([NotifyKit.status(id).state, fake.received.size]).to eq(["unknown_outcome", 0])
    end
  end

  context "when many workers poll concurrently" do
    it "sends every message exactly once" do
      20.times { |i| pay_order("O#{i}") }
      in_threads(4) { NotifyKit.dispatch_due(limit: 20) }
      aggregate_failures do
        expect(fake.received.size).to eq(20)
        expect(fake.received.map { |r| r[:context].message_id }.uniq.size).to eq(20)
        expect(NotifyKit::Records::Message.in_state("accepted").count).to eq(20)
      end
    end
  end
end
