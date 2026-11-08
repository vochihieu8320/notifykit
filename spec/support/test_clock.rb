# frozen_string_literal: true

# Controllable clock injected through NotifyKit::Configuration#clock.
class TestClock
  attr_reader :now

  def initialize(now = Time.utc(2026, 11, 8, 9, 0, 0))
    @now = now
    @mutex = Mutex.new
  end

  def call = @mutex.synchronize { @now }

  def advance(seconds)
    @mutex.synchronize { @now += seconds }
  end
end
