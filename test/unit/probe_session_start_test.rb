# frozen_string_literal: true

require "test_helper"
require_relative "../fixtures/probe/target_app"

# Session.start's own rescue (Registry.release + reraise, wrapping
# `new(...).enable!`) and Session#enable!'s own rescue (disable every
# trace point built so far, release RaiseTracker, reraise) both guard
# against a target that fails mid-enable -- a genuinely reachable
# branch, not hook-blind, but with no natural trigger available (a
# stale UnboundMethod still binds cleanly; a second TracePoint on the
# same target does not conflict -- both tried directly and neither
# raises). RaiseTracker.instance is the one real seam #enable! already
# calls first, so patching #acquire on that one shared, process-wide
# singleton -- always through `super`, so the real acquire still runs
# and RaiseTracker's own invariants stay intact -- forces both rescues
# with a single real Session.start call, the same "patch one real
# collaborator to fail" technique record_events_test.rb and
# capture_test.rb already use for their own hook-failure tests.
class ProbeSessionStartTest < Minitest::Test
  def test_start_and_enable_release_their_reservations_and_reraise_on_a_mid_enable_failure
    tracker = Bulldogger::Probe::RaiseTracker.instance
    def tracker.acquire
      super
      raise "boom mid-enable"
    end
    run = Bulldogger::Run.new(config: Bulldogger.config)

    error = assert_raises(RuntimeError) do
      Bulldogger::Probe::Session.start(["Billing::Invoice#amount"], config: Bulldogger.config, run: run)
    end
    assert_equal "boom mid-enable", error.message

    # RaiseTracker's own ref-count invariant must still balance: the
    # patched #acquire really ran (via super) before raising, so
    # #enable!'s rescue must have released it back to where a later,
    # unrelated probe session finds it unheld.
    refute tracker.instance_variable_get(:@refcount).positive?
  ensure
    tracker.singleton_class.send(:remove_method, :acquire)
  end

  # Same failure, checked from Registry's side: a target that failed
  # mid-enable must not stay reserved, or a later probe of the exact
  # same target is refused for the rest of the process.
  def test_a_target_that_failed_mid_enable_can_be_probed_again_afterward
    tracker = Bulldogger::Probe::RaiseTracker.instance
    def tracker.acquire
      super
      raise "boom mid-enable"
    end
    run = Bulldogger::Run.new(config: Bulldogger.config)

    assert_raises(RuntimeError) do
      Bulldogger::Probe::Session.start(["Billing::Invoice#amount"], config: Bulldogger.config, run: run)
    end
    tracker.singleton_class.send(:remove_method, :acquire)

    session = Bulldogger::Probe::Session.start(["Billing::Invoice#amount"], config: Bulldogger.config, run: run)
    refute_nil session
    session.finish
  ensure
    if tracker.singleton_class.instance_methods(false).include?(:acquire)
      tracker.singleton_class.send(:remove_method, :acquire)
    end
  end
end
