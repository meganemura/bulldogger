# frozen_string_literal: true

# A real, small, fully passing suite: the acceptance suite runs this
# as a child process and checks that no run directory is created --
# the zero-cost-when-green claim demonstrated by execution, not by
# reading the source.
require "bulldogger/minitest"
require "minitest/autorun"

class GreenTest < ::Minitest::Test
  def test_it_passes
    assert_equal 4, 2 + 2
  end
end
