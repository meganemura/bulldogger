# frozen_string_literal: true

require "test_helper"
require_relative "../support/real_trace_point"

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

  # capture(tp) is only ever called from inside Capture's :raise hook
  # in production, which stdlib Coverage cannot reliably observe (see
  # test/unit/tracepoint_coverage_blind_spot_test.rb). Every test above
  # goes through that real hook; these call #capture directly instead,
  # so the frame/locals-building methods it drives are visible to
  # Coverage too.

  def test_capture_called_directly_in_capture_frames_mode_builds_real_frames
    Bulldogger.config.frame_source = :capture_frames
    frame_source = build_frame_source

    qty = 42
    rows = [1, 2, 3]
    [qty, rows] # read once so -w doesn't call these unused
    frames, omitted = frame_source.capture(nil) # capture_frames mode never reads tp

    assert_equal 0, omitted
    frame_with_qty = frames.find { |f| f["locals"].key?("qty") }
    refute_nil frame_with_qty, "this test's own frame must appear with its locals"
    assert_equal({ "value" => "42" }, frame_with_qty["locals"]["qty"])
    assert_equal({ "value" => "[1, 2, 3]" }, frame_with_qty["locals"]["rows"])
  end

  def test_capture_called_directly_in_capture_frames_mode_reports_frames_omitted_when_cut
    Bulldogger.config.frame_source = :capture_frames
    Bulldogger.config.max_frames = 1
    frame_source = build_frame_source

    _frames, omitted = frame_source.capture(nil)

    assert_operator omitted, :>, 0
  end

  def test_capture_called_directly_in_degraded_mode_reads_frame_zeros_locals_from_the_real_binding
    Bulldogger.config.frame_source = :degraded
    frame_source = build_frame_source
    tp = Bulldogger::TestSupport.capture_raise { raise_with_a_local }

    frames, = frame_source.capture(tp)

    assert frames[0].key?("locals")
    assert_equal({ "value" => "9" }, frames[0]["locals"]["qty"])
    assert_equal "degraded", frame_source.mode.to_s
  end

  # capture_frames_available?'s own LoadError rescue: this repo's own
  # bundle always has the debug gem (a dev dependency), so this branch
  # needs `require "debug/frame_info"` to fail for real -- scoped to
  # this one throwaway instance's singleton class, not Kernel itself,
  # so no other test or process-wide state is touched.
  def test_capture_frames_available_returns_false_when_debug_frame_info_cannot_be_loaded
    frame_source = build_frame_source
    def frame_source.require(name)
      raise LoadError, "cannot load such file -- #{name}" if name == "debug/frame_info"

      super
    end

    refute frame_source.send(:capture_frames_available?)
  end

  # degraded_locations' fallback: caller_locations, filtered the same
  # way as capture_frames' own skip prefix, used only when the raised
  # exception's own backtrace_locations is nil. A real raise always
  # populates backtrace_locations, so this needs a real captured
  # raised_exception whose #backtrace_locations is overridden to
  # return nil -- the double's contract is "the necessary facet only",
  # and here that facet is deliberately unavailable, matching what a
  # real (if rare) exception with no backtrace could report.
  def test_capture_called_directly_in_degraded_mode_falls_back_to_caller_locations_when_backtrace_locations_is_nil
    Bulldogger.config.frame_source = :degraded
    frame_source = build_frame_source
    tp = Bulldogger::TestSupport.capture_raise { raise_with_a_local }
    def tp.raised_exception
      exc = super
      def exc.backtrace_locations
        nil
      end
      exc
    end

    frames, = frame_source.capture(tp)

    refute_empty frames
  end

  def test_capture_called_directly_in_degraded_mode_marks_locals_unavailable_past_frame_zero
    Bulldogger.config.frame_source = :degraded
    frame_source = build_frame_source
    tp = Bulldogger::TestSupport.capture_raise { level_a_for_direct_capture }

    frames, = frame_source.capture(tp)

    assert_operator frames.size, :>=, 2
    assert_equal true, frames[1]["locals_unavailable"]
  end

  private

  def build_frame_source
    redactor = Bulldogger::Redactor.new(Bulldogger.config.redact_patterns)
    formatter = Bulldogger::Formatter.new(config: Bulldogger.config, redactor: redactor)
    Bulldogger::FrameSource.new(config: Bulldogger.config, formatter: formatter, redactor: redactor)
  end

  def raise_with_a_local
    qty = 9
    [qty]
    raise "boom"
  end

  def level_a_for_direct_capture
    level_b_for_direct_capture
  end

  def level_b_for_direct_capture
    raise "boom"
  end

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
