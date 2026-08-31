# frozen_string_literal: true

# A failure exception that is already frozen when it's raised. The
# reporter prints the evidence line to its own io and never mutates
# the exception, so this fixture guards that a frozen failure still
# gets its line.
require "bulldogger/minitest"
require "minitest/autorun"

class FrozenFailureTest < ::Minitest::Test
  def test_frozen_assertion_failure
    raise ::Minitest::Assertion.new("boom").freeze
  end
end
