# frozen_string_literal: true

require "test_helper"

class FrameSourceTest < Minitest::Test
  def test_degrade_mode_gives_locals_only_to_frame_zero
    Bulldogger.config.frame_source = :degraded
    Bulldogger.start

    exception = outer_degrade_call
    snapshot = Bulldogger.snapshot_for(exception)

    assert_equal "degraded", snapshot["capture_mode"]
    frames = snapshot["frames"]
    assert_operator frames.size, :>=, 2
    assert frames[0].key?("locals")
    refute frames[1].key?("locals")
    assert_equal true, frames[1]["locals_unavailable"]
  end

  def test_capture_frames_mode_hides_bulldoggers_own_frames
    Bulldogger.config.frame_source = :capture_frames
    Bulldogger.start

    exception = trigger_simple_raise
    snapshot = Bulldogger.snapshot_for(exception)
    refute_nil snapshot

    lib_dir = File.expand_path("../../lib/bulldogger", __dir__)
    paths = snapshot["frames"].filter_map { |frame| frame["path"] }
    refute paths.any? { |path| path.start_with?(lib_dir) }
  end

  def test_frames_and_locals_omitted_are_reported_when_cut
    Bulldogger.config.max_frames = 2
    Bulldogger.config.max_locals = 1
    Bulldogger.config.frame_source = :capture_frames
    Bulldogger.start

    exception = deeply_nested_raise
    snapshot = Bulldogger.snapshot_for(exception)

    assert_operator snapshot["frames_omitted"], :>, 0
    assert_operator snapshot["frames"][0]["locals_omitted"], :>, 0
  end

  private

  def outer_degrade_call
    inner_degrade_raise
  rescue RuntimeError => e
    e
  end

  def inner_degrade_raise
    qty = 7
    [qty]
    raise "boom"
  end

  def trigger_simple_raise
    raise "boom"
  rescue RuntimeError => e
    e
  end

  def deeply_nested_raise
    level_a
  rescue RuntimeError => e
    e
  end

  def level_a
    level_b
  end

  def level_b
    level_c
  end

  def level_c
    qty = 1
    rows = 2
    blob = 3
    [qty, rows, blob]
    raise "boom"
  end
end
