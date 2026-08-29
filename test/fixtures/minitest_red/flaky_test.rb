# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../../lib", __dir__))
require "bulldogger/minitest"
require "minitest/autorun"

class FlakyReplayTest < Minitest::Test
  def test_passes_only_during_replay
    assert_equal "1", ENV["BULLDOGGER_REPLAY_CHILD"]
  end
end
