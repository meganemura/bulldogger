# frozen_string_literal: true

require "test_helper"

# Pending's real caller (Capture#handle_raise) only ever calls #put
# from inside the :raise TracePoint hook, which stdlib Coverage cannot
# reliably observe (see test/unit/tracepoint_coverage_blind_spot_test.rb). #put takes no TracePoint
# object at all -- exception and snapshot are plain values -- so it is
# fully testable directly, driven by real raises for the exception
# identity #put's own first-write-wins rule depends on.
class PendingTest < Minitest::Test
  def setup
    super
    @pending = Bulldogger::Pending.new(2)
  end

  def test_put_then_get_returns_the_same_snapshot
    exception = raise_and_rescue("a")

    @pending.put(exception, { "capture_mode" => "capture_frames" })

    assert_equal({ "capture_mode" => "capture_frames" }, @pending.get(exception))
  end

  # First-write-wins: a re-raised exception fires :raise a second time
  # from the rescue frame, but that second capture is worth less than
  # the first (it points at the handler, not the bug).
  def test_a_second_put_for_the_same_exception_is_ignored
    exception = raise_and_rescue("a")

    @pending.put(exception, { "capture_mode" => "capture_frames" })
    @pending.put(exception, { "capture_mode" => "degraded" })

    assert_equal({ "capture_mode" => "capture_frames" }, @pending.get(exception))
  end

  def test_get_for_an_unknown_exception_is_nil
    assert_nil @pending.get(raise_and_rescue("unknown"))
  end

  def test_put_past_max_size_evicts_the_oldest_and_marks_it_evicted
    first = raise_and_rescue("a")
    second = raise_and_rescue("b")
    third = raise_and_rescue("c")

    @pending.put(first, { "capture_mode" => "capture_frames" })
    @pending.put(second, { "capture_mode" => "capture_frames" })
    @pending.put(third, { "capture_mode" => "capture_frames" })

    assert_nil @pending.get(first)
    assert @pending.evicted?(first)
    refute_nil @pending.get(second)
    refute_nil @pending.get(third)
    refute @pending.evicted?(second)
  end

  def test_evicted_is_false_for_an_exception_never_put_at_all
    refute @pending.evicted?(raise_and_rescue("never put"))
  end

  private

  def raise_and_rescue(message)
    raise message
  rescue RuntimeError => e
    e
  end
end
