# frozen_string_literal: true

require "minitest/autorun"
require "bulldogger/minitest"

class SpawnFramesTest < Minitest::Test
  def test_spawn
    script = "def grandchild_only; :child; end; grandchild_only"
    assert system(RbConfig.ruby, "-e", script)
  end
end
