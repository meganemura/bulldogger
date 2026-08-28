# frozen_string_literal: true

require "test_helper"

# RaiseTracker's real caller (Probe::Session's TracePoint block) only
# ever calls push_checkpoint/pop_and_raised_exit? from inside a
# TracePoint hook, which stdlib Coverage cannot reliably observe (see
# the task report). Neither method takes a TracePoint object, though
# -- the checkpoint bookkeeping is pure Thread.current state -- so it
# is fully testable directly, driven by real raises instead of a hook.
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
end
