# frozen_string_literal: true

RSpec.describe NotifyKit::Providers::Zalo::Zns do
  let(:message) do
    NotifyKit::Message.new(provider: :shop_zalo, to: "0912 345 678", template: "231802",
                           data: { customer_name: "An", order_code: "A1" })
  end
  let(:context) { NotifyKit::DeliveryContext.new(message_id: 77, attempt_number: 1) }

  before { zalo_mock.reset! }

  describe "#deliver" do
    context "when Zalo accepts" do
      it "sends the normalized phone, template data and our message id as tracking_id" do
        response = zalo_provider.deliver(message, context)
        aggregate_failures do
          expect(response.provider_message_id).to eq("zmsg-1")
          expect(zalo_mock.sent.first).to include(
            "phone" => "84912345678", "template_id" => "231802", "tracking_id" => "77",
            "template_data" => { "customer_name" => "An", "order_code" => "A1" }
          )
        end
      end
    end

    context "when the access token expired server-side" do
      it "refreshes once and resends" do
        store = zalo_token_store
        zalo_mock.expire_access_token!
        zalo_provider(token_store: store).deliver(message, context)
        aggregate_failures do
          expect(zalo_mock.refresh_calls).to eq(1)
          expect(zalo_mock.sent.size).to eq(1)
          expect(store.fetch("shop_zalo").refresh_token).to eq("refresh-2")
        end
      end
    end

    context "when the stored token is about to expire" do
      it "refreshes proactively before sending" do
        zalo_provider(token_store: zalo_token_store(expires_in: 60)).deliver(message, context)
        expect([zalo_mock.refresh_calls, zalo_mock.sent.size]).to eq([1, 1])
      end
    end

    context "when Zalo returns an unmapped error code" do
      it "raises PermanentFailure with the provider code" do
        zalo_mock.enqueue([:error, -9999])
        expect { zalo_provider.deliver(message, context) }
          .to raise_error(NotifyKit::PermanentFailure) { |e| expect(e.provider_code).to eq(-9999) }
      end
    end

    context "when the app maps an extra error code" do
      it "uses the configured category" do
        zalo_mock.enqueue([:error, -124])
        provider = zalo_provider(error_codes: { -124 => :not_eligible })
        expect { provider.deliver(message, context) }.to raise_error(NotifyKit::NotEligible)
      end
    end

    context "when Zalo answers 500" do
      it "treats the outcome as unknown" do
        zalo_mock.enqueue(:server_error)
        expect { zalo_provider.deliver(message, context) }.to raise_error(NotifyKit::UnknownOutcome)
      end
    end

    context "when the server is unreachable" do
      it "raises TransientFailure" do
        provider = described_class.new(name: :shop_zalo, transport: NotifyKit::Transports::NetHttp.new,
                                       app_id: "a", app_secret: "s", token_store: zalo_token_store,
                                       urls: { business: "http://127.0.0.1:1" })
        expect { provider.deliver(message, context) }.to raise_error(NotifyKit::TransientFailure)
      end
    end
  end

  describe "#validate!" do
    it "rejects a non-Vietnamese number" do
      bad = message.with(to: "+1 415 555 0100")
      expect { zalo_provider.validate!(bad) }.to raise_error(NotifyKit::InvalidRecipient)
    end

    it "requires a template" do
      expect { zalo_provider.validate!(message.with(template: nil)) }.to raise_error(NotifyKit::InvalidTemplate)
    end
  end
end
