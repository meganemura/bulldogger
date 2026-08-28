# frozen_string_literal: true

require "test_helper"
require_relative "../support/real_trace_point"

class CaptureTest < Minitest::Test
  def test_locals_and_frame_position_appear_in_the_snapshot
    Bulldogger.start

    exception, line = trigger_raise_with_locals
    snapshot = Bulldogger.snapshot_for(exception)
    frame0 = snapshot["frames"][0]

    assert_equal({ "value" => "3" }, frame0["locals"]["qty"])
    assert_equal({ "value" => "[1, 2, 3]" }, frame0["locals"]["rows"])
    assert_equal __FILE__, frame0["path"]
    assert_equal line, frame0["line"]
    assert_includes frame0["label"], "trigger_raise_with_locals"
  end

  def test_reraise_keeps_the_first_captures_frame
    Bulldogger.start

    exception, first_line = trigger_reraise
    snapshot = Bulldogger.snapshot_for(exception)

    assert_equal first_line, snapshot["frames"][0]["line"]
  end

  def test_hook_never_lets_an_exception_escape_into_the_app
    Bulldogger.start
    formatter = Bulldogger.send(:capture).instance_variable_get(:@formatter)
    def formatter.format(*)
      raise "formatter exploded"
    end

    message =
      begin
        raise "app error"
      rescue RuntimeError => e
        e.message
      end

    assert_equal "app error", message
  end

  def test_pending_ring_evicts_the_oldest_entries
    Bulldogger.config.max_pending = 2
    Bulldogger.start

    exceptions = Array.new(5) { |i| raise_numbered(i) }

    exceptions.first(3).each { |e| assert_nil Bulldogger.snapshot_for(e) }
    exceptions.last(2).each { |e| refute_nil Bulldogger.snapshot_for(e) }
  end

  # handle_raise is the :raise hook body itself (`TracePoint.new(:raise)
  # { |tp| handle_raise(tp) }`), so every test above -- which goes
  # through Bulldogger.start's real hook -- exercises it in a way
  # stdlib Coverage cannot see (see test/unit/tracepoint_coverage_blind_spot_test.rb). It takes a
  # single TracePoint argument, so it is fully testable directly, with
  # a double built from a real raise instead of a live hook.
  def test_handle_raise_called_directly_stores_a_snapshot_pending_can_return
    Bulldogger.config.frame_source = :capture_frames
    capture = Bulldogger::Capture.new(config: Bulldogger.config)
    tp = Bulldogger::TestSupport.capture_raise { raise "boom" }

    capture.send(:handle_raise, tp)

    snapshot = capture.snapshot_for(tp.raised_exception)
    refute_nil snapshot
    assert_equal "capture_frames", snapshot["capture_mode"]
  end

  def test_handle_raise_called_directly_reports_frames_omitted_only_when_cut
    Bulldogger.config.frame_source = :capture_frames
    Bulldogger.config.max_frames = 1
    capture = Bulldogger::Capture.new(config: Bulldogger.config)
    tp = Bulldogger::TestSupport.capture_raise { deeply_nested_for_capture }

    capture.send(:handle_raise, tp)

    snapshot = capture.snapshot_for(tp.raised_exception)
    assert_operator snapshot["frames_omitted"], :>, 0
  end

  # Same guarantee as the hook-based test above (a formatting failure
  # inside the hook must not escape into the app's own raise path),
  # exercised here by calling handle_raise directly so the guard
  # itself -- not just the fact that it holds -- is what Coverage sees.
  def test_handle_raise_called_directly_swallows_its_own_internal_failure
    capture = Bulldogger::Capture.new(config: Bulldogger.config)
    frame_source = capture.instance_variable_get(:@frame_source)
    def frame_source.capture(*)
      raise "frame_source exploded"
    end
    tp = Bulldogger::TestSupport.capture_raise { raise "boom" }

    result = capture.send(:handle_raise, tp)

    assert_nil result
    assert_nil capture.snapshot_for(tp.raised_exception)
  end

  private

  def deeply_nested_for_capture
    qty = 1
    rows = 2
    [qty, rows]
    raise "boom"
  end

  def trigger_raise_with_locals
    qty = 3
    rows = [1, 2, 3]
    [qty, rows] # read once so -w doesn't call these unused; capture reads them via binding, not this line
    line = __LINE__ + 1
    raise ArgumentError, "boom"
  rescue ArgumentError => e
    [e, line]
  end

  def trigger_reraise
    begin
      line = __LINE__ + 1
      raise "boom"
    rescue RuntimeError => e
      begin
        raise e
      rescue RuntimeError => e2
        return [e2, line]
      end
    end
  end

  def raise_numbered(i)
    raise "boom #{i}"
  rescue RuntimeError => e
    e
  end
end
