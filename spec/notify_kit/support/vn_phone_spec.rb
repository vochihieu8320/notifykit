# frozen_string_literal: true

RSpec.describe NotifyKit::Support::VnPhone do
  describe ".normalize" do
    {
      "0912345678" => "84912345678",
      "0912 345 678" => "84912345678",
      "+84 912-345-678" => "84912345678",
      "84987654321" => "84987654321",
      "(036) 123.4567" => "84361234567"
    }.each do |raw, expected|
      it "normalizes #{raw.inspect}" do
        expect(described_class.normalize(raw)).to eq(expected)
      end
    end

    ["", "12345", "0212345678", "+1 415 555 0100", "09123456789"].each do |raw|
      it "rejects #{raw.inspect}" do
        expect(described_class.normalize(raw)).to be_nil
      end
    end
  end

  describe ".normalize!" do
    it "raises InvalidRecipient without leaking the full number" do
      expect { described_class.normalize!("0212345678") }
        .to raise_error(NotifyKit::InvalidRecipient, /021\*\*\*\*678/)
    end
  end
end
