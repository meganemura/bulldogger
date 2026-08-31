# frozen_string_literal: true

require "minitest/autorun"
require "bulldogger/minitest"

def rescued
  raise "handled"
rescue RuntimeError
  :handled
end

def outer
  rescued
end

class MinitestFramesTest < Minitest::Test
  def test_frames
    assert_equal :handled, outer
  end
end
