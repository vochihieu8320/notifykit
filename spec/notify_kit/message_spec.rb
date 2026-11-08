# frozen_string_literal: true

RSpec.describe NotifyKit::Message do
  def build(**overrides)
    described_class.new(provider: :fake, to: "0912345678", template: "t1",
                        data: { order: "A1", amount: 100 }, **overrides)
  end

  describe "#fingerprint" do
    it "ignores hash key order and symbol/string keys" do
      reordered = build(data: { "amount" => 100, "order" => "A1" })
      expect(reordered.fingerprint).to eq(build.fingerprint)
    end

    it "changes when the payload changes" do
      expect(build(data: { order: "B2", amount: 100 }).fingerprint).not_to eq(build.fingerprint)
    end

    it "ignores the idempotency key" do
      expect(build(idempotency_key: "x").fingerprint).to eq(build(idempotency_key: "y").fingerprint)
    end
  end

  it "is immutable" do
    expect { build.data["order"] = "hack" }.to raise_error(FrozenError)
  end
end
