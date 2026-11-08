# frozen_string_literal: true

module NotifyKit
  module Records
    module Concerns
      # At most one row per (namespace, idempotency_key), enforced by a UNIQUE index,
      # not by a racy "SELECT then INSERT". The insert runs in a SAVEPOINT so that a
      # unique violation does not abort the caller's surrounding transaction (Postgres
      # aborts the whole transaction on any error otherwise).
      module Idempotent
        extend ActiveSupport::Concern

        included do
          validates :payload_fingerprint, presence: true
        end

        class_methods do
          # @return [Array(record, Boolean)] the row and whether this call created it
          def insert_idempotently!(attrs)
            [transaction(requires_new: true) { create!(attrs) }, true]
          rescue ::ActiveRecord::RecordNotUnique
            existing = find_by!(namespace: attrs[:namespace], idempotency_key: attrs[:idempotency_key])
            unless existing.same_payload?(attrs[:payload_fingerprint])
              raise IdempotencyConflict.new("idempotency key #{attrs[:idempotency_key].inspect} reused with a " \
                                            "different payload", message_id: existing.id)
            end

            [existing, false]
          end
        end

        def same_payload?(fingerprint) = payload_fingerprint == fingerprint
      end
    end
  end
end
