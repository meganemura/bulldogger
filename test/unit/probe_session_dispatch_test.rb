# frozen_string_literal: true

require "test_helper"

# Session#dispatch is the probe TracePoint hook's body (`TracePoint.new
# (:call, :return) { |tp| dispatch(tp, stats) }`), only ever called
# from inside that hook in production, which stdlib Coverage cannot
# reliably observe (see test/unit/tracepoint_coverage_blind_spot_test.rb). dispatch only ever reads
# tp.event -- everything else it does routes through RaiseTracker (its
# own real singleton) or is handed untouched to stats -- so a double
# needs only an #event method; no captured-real-tp fidelity concern
# applies to a field this method never reads.
class ProbeSessionDispatchTest < Minitest::Test
  TPStub = Struct.new(:event)

  RecordingStats = Struct.new(:calls, :returns) do
    def initialize
      super([], [])
    end

    def record_call(tp, caller_location)
      calls << [tp, caller_location]
    end

    def record_return(tp, raised:)
      returns << [tp, raised]
    end
  end

  def setup
    super
    @tracker = Bulldogger::Probe::RaiseTracker.instance
    @tracker.acquire
  end

  def teardown
    @tracker.release
    super
  end

  def test_dispatch_on_call_pushes_a_checkpoint_and_forwards_to_record_call
    session = new_session
    stats = RecordingStats.new
    tp = TPStub.new(:call)

    session.send(:dispatch, tp, stats)

    assert_equal 1, stats.calls.size
    assert_same tp, stats.calls.first[0]
  end

  def test_dispatch_on_return_pops_the_checkpoint_and_forwards_raised_false_when_nothing_raised
    session = new_session
    stats = RecordingStats.new
    @tracker.push_checkpoint

    session.send(:dispatch, TPStub.new(:return), stats)

    assert_equal 1, stats.returns.size
    assert_equal false, stats.returns.first[1]
  end

  def test_dispatch_on_return_forwards_raised_true_when_a_raise_is_still_unwinding
    session = new_session
    stats = RecordingStats.new
    @tracker.push_checkpoint

    begin
      raise "boom"
    ensure
      session.send(:dispatch, TPStub.new(:return), stats)
    end
  rescue RuntimeError
    assert_equal true, stats.returns.first[1]
  end

  # Same rule as Capture's :raise hook: the probe hook must never let
  # an exception from its own internals escape into the probed
  # method's own call/return path.
  def test_dispatch_swallows_its_own_internal_failure
    session = new_session
    exploding_stats = Object.new
    def exploding_stats.record_call(*)
      raise "stats exploded"
    end

    session.send(:dispatch, TPStub.new(:call), exploding_stats)
  end

  private

  # targets: [] and run: nil are safe here -- dispatch never touches
  # @targets or @run, only RaiseTracker.instance (a real, shared
  # singleton) and whatever stats double this test passes in directly.
  def new_session
    Bulldogger::Probe::Session.new(targets: [], config: Bulldogger.config, run: nil)
  end
end
