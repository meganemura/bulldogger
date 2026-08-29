# frozen_string_literal: true

# Stands in for a real project's test/test_helper.rb: signature_test.rb
# reaches this file with a plain `require`, never require_relative,
# trusting whatever put this directory on $LOAD_PATH -- a Rakefile's
# Rake::TestTask `-Itest`, in a real project; the acceptance test that
# runs this fixture passes the same -I flag by hand, to the outer
# process only. That is the one structural feature red_test.rb and
# flaky_test.rb do not have: a require that only resolves through
# $LOAD_PATH, never through this file's own location on disk. A
# replay child that does not forward the parent's $LOAD_PATH cannot
# resolve it, which is exactly the bug measured against a real gem
# (crmne/archspec, whose own test files require "test_helper" the
# same way).
require "bulldogger/minitest"
require "minitest/autorun"

module Signature
  # The value must be produced and returned before the caller's
  # assertion fails (see signature_test.rb): a method that raises
  # instead would leave its own frame on the exception's own
  # backtrace, which the failure snapshot already reaches without any
  # help from replay -- masking exactly the gap replay exists to fill.
  def self.accepts_arity?(required, given)
    required <= given
  end
end
