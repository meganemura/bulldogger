# frozen_string_literal: true

require "minitest/autorun"
require "bulldogger/minitest"

def stable_branch
  :stable
end

def alternate_branch
  :alternate
end

class UnstableFramesTest < Minitest::Test
  def test_changes_its_application_frames
    marker = File.join(ENV.fetch("BULLDOGGER_OUTPUT_DIR"), "unstable-run-marker")
    branch = File.exist?(marker) ? alternate_branch : stable_branch
    File.write(marker, "seen")

    assert branch
  end
end
