# frozen_string_literal: true

module NotifyKit
  module Records
    module Concerns
      # Work-queue semantics on a table: competing workers claim rows with
      # SELECT ... FOR UPDATE SKIP LOCKED (each row goes to exactly one worker, nobody
      # blocks), and hold them with a time-limited lease. A row whose lease expired is
      # claimable again, which is how a crashed worker's work gets recovered.
      module Leasable
        extend ActiveSupport::Concern

        included do
          scope :claimable, lambda { |now|
            where(state: States::DISPATCHABLE, available_at: ..now)
              .or(where(state: States::SENDING, locked_until: ..now))
          }
        end

        class_methods do
          def claim!(worker_id:, now:, lease_seconds:, limit:, ids: nil)
            transaction do
              scope = claimable(now).order(:available_at, :id).limit(limit)
              scope = scope.where(id: ids) if ids
              claimed_ids = scope.lock(skip_locked_clause).pluck(:id)
              if claimed_ids.any?
                where(id: claimed_ids).update_all(state: States::SENDING, locked_by: worker_id,
                                                  locked_until: now + lease_seconds, updated_at: now)
              end
              where(id: claimed_ids).order(:available_at, :id).to_a
            end
          end

          # Fenced update: only the current lease holder may move the row on.
          # @return [Boolean] false when the lease was lost to another worker
          def release!(id, worker_id:, attrs:)
            where(id:, locked_by: worker_id, state: States::SENDING)
              .update_all(attrs.merge(locked_by: nil, locked_until: nil)) == 1
          end

          private

          def skip_locked_clause
            adapter = connection.adapter_name.downcase
            # SQLite serialises writers and has no row locks; everything else used in
            # production (PostgreSQL, MySQL 8+) supports SKIP LOCKED.
            adapter.include?("sqlite") ? false : "FOR UPDATE SKIP LOCKED"
          end
        end
      end
    end
  end
end
