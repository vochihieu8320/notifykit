# frozen_string_literal: true

module NotifyKit
  # Passed to Provider#deliver so vendors can tag requests (e.g. Zalo tracking_id).
  DeliveryContext = Data.define(:message_id, :attempt_number)
end
