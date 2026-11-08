# frozen_string_literal: true

module NotifyKit
  module TokenStores
    # Tokens in the host database, shared by every process/worker.
    #
    # `with_lock` holds a row lock (SELECT ... FOR UPDATE) for the duration of the
    # refresh, so concurrent workers queue up behind the first one and then see the
    # token it already refreshed. Holding a DB transaction across one HTTP call is a
    # deliberate trade-off: refreshes are rare (about once a day) and a burned refresh
    # token would need a human to re-authorise the OA.
    class ActiveRecordStore
      include Ports::TokenStore

      def fetch(key) = Records::ProviderToken.find_by(key: key.to_s)&.to_token

      def save(key, token)
        record = Records::ProviderToken.find_or_initialize_by(key: key.to_s)
        record.assign_token(token)
        record.save!
        token
      end

      def with_lock(key)
        ensure_row(key.to_s)
        Records::ProviderToken.transaction do
          record = Records::ProviderToken.lock.find_by!(key: key.to_s)
          result = yield record.to_token
          if result.is_a?(Token)
            record.assign_token(result)
            record.save!
          end
          result
        end
      end

      private

      # The row must exist to be locked. create_or_find_by relies on the unique index,
      # so concurrent first-time callers do not race.
      def ensure_row(key)
        Records::ProviderToken.create_or_find_by!(key:)
      end
    end
  end
end
