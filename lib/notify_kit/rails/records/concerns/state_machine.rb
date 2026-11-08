# frozen_string_literal: true

module NotifyKit
  module Records
    module Concerns
      # Allowed lifecycle transitions (see NotifyKit::States). Terminal states have
      # no outgoing edges, so late or duplicate updates cannot move a message backwards.
      module StateMachine
        extend ActiveSupport::Concern

        TRANSITIONS = {
          States::QUEUED => [States::SENDING],
          States::RETRY_SCHEDULED => [States::SENDING],
          States::SENDING => [States::ACCEPTED, States::RETRY_SCHEDULED, States::FAILED, States::UNKNOWN_OUTCOME,
                              States::SENDING],
          States::ACCEPTED => [],
          States::FAILED => [],
          States::UNKNOWN_OUTCOME => []
        }.freeze

        included do
          validates :state, inclusion: { in: States::ALL }
          scope :in_state, ->(*states) { where(state: states.flatten) }
        end

        class_methods do
          def transition_allowed?(from, to) = TRANSITIONS.fetch(from, []).include?(to)
        end

        def terminal? = States::TERMINAL.include?(state)
      end
    end
  end
end
