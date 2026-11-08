# frozen_string_literal: true

module NotifyKit
  # ActiveRecord models backing ActiveRecordStorage / ActiveRecordStore.
  # Namespaced under Records so they never clash with NotifyKit::Message (the value object).
  module Records
    class ApplicationRecord < ::ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
