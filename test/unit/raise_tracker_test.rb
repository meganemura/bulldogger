# frozen_string_literal: true

require "test_helper"
require_relative "../support/real_trace_point"

# RaiseTracker's real caller (Probe::Session's TracePoint block) only
# ever calls push_checkpoint/pop_and_raised_exit? from inside a
# TracePoint hook, which stdlib Coverage cannot reliably observe (see
# test/unit/tracepoint_coverage_blind_spot_test.rb). Neither method
# takes a TracePoint object, though -- the checkpoint bookkeeping is
# pure Thread.current state -- so it is fully testable directly,
# driven by real raises instead of a hook.
#
# on_raise/on_rescue are RaiseTracker's own hook bodies (subscribed by
# #acquire, called only from inside their own :raise/:rescue
# TracePoints), so those two are tested the other way: called
# directly with a real captured tp double, outside any TracePoint.
class RaiseTrackerTest < Minitest::Test
  def setup
    super
    @tracker = Bulldogger::Probe::RaiseTracker.instance
    @tracker.acquire
  end

  def teardown
    @tracker.release
    super
  end

  def test_pop_and_raised_exit_is_false_when_nothing_raised_since_the_checkpoint
    @tracker.push_checkpoint

    refute @tracker.pop_and_raised_exit?
  end

  # ensure, not rescue: it runs while the exception is still
  # unwinding, before any rescue clause has matched it -- the same
  # window contract-verbs.md's :return discriminator relies on (the
  # caller's own :rescue fires only after :return).
  def test_pop_and_raised_exit_is_true_while_a_raise_is_still_unwinding
    @tracker.push_checkpoint

    begin
      raise "boom"
    ensure
      assert @tracker.pop_and_raised_exit?
      assert_equal "RuntimeError", @tracker.current_exception_class_name
    end
  rescue RuntimeError
    nil
  end

  def test_pop_and_raised_exit_is_false_when_the_raise_was_rescued_before_popping
    @tracker.push_checkpoint

    begin
      raise "boom"
    rescue RuntimeError
      nil
    end

    refute @tracker.pop_and_raised_exit?
  end

  def test_on_raise_increments_the_counter_and_records_the_exception_class_name
    tp = Bulldogger::TestSupport.capture_raise { raise "boom" }

    @tracker.push_checkpoint
    @tracker.send(:on_raise, tp)

    assert @tracker.pop_and_raised_exit?
    assert_equal "RuntimeError", @tracker.current_exception_class_name
  end

  def test_on_rescue_decrements_the_counter
    tp = Bulldogger::TestSupport.capture_raise { raise "boom" }
    @tracker.push_checkpoint
    @tracker.send(:on_raise, tp)

    @tracker.send(:on_rescue)

    refute @tracker.pop_and_raised_exit?
  end

  # exception_class_name's own rescue: an exception class whose own
  # .name raises must fall back to "Object" rather than take this
  # hook down with it.
  def test_exception_class_name_falls_back_to_object_when_the_class_name_raises
    exception = BrokenClassName.new("boom")

    assert_equal "Object", @tracker.send(:exception_class_name, exception)
  end

  # on_raise/on_rescue's own top-level rescue: neither must let an
  # internal failure escape into the app's own raise/rescue path (same
  # rule as every other hook body in this codebase). #counter is
  # patched on this one shared singleton instance only, and restored
  # in ensure, since RaiseTracker.instance is process-wide state every
  # other test also relies on.
  def test_on_raise_and_on_rescue_swallow_their_own_internal_failure
    def @tracker.counter
      raise "counter exploded"
    end
    tp = Bulldogger::TestSupport.capture_raise { raise "boom" }

    @tracker.send(:on_raise, tp)
    @tracker.send(:on_rescue)
  ensure
    @tracker.singleton_class.send(:remove_method, :counter)
  end

  class BrokenClassName < StandardError
    def self.name
      raise "no name for you"
    end
  end
end
