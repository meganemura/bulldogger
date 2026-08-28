# frozen_string_literal: true

# Mirrors test/fixtures/minitest_red/frozen_failure_test.rb: a failure
# exception that is already frozen when it's raised. Bulldogger::RSpec
# .annotate!'s usual move (tag the exception's own #message with the
# evidence path) raises FrozenError on an object like this, and must
# fall back to printing the line itself instead of losing it.
require_relative "spec_helper"

RSpec.describe "FrozenFailure" do
  it "raises an already-frozen exception" do
    raise RuntimeError.new("boom").freeze
  end
end
