# frozen_string_literal: true

# A failure exception that is already frozen when it's raised: the
# reporter's usual move (tag the exception's own #message with the
# evidence path) raises FrozenError on an object like this, and must
# fall back to printing the line itself instead of losing it.
require "bulldogger/minitest"
require "minitest/autorun"

class FrozenFailureTest < ::Minitest::Test
  def test_frozen_assertion_failure
    raise ::Minitest::Assertion.new("boom").freeze
  end
end
