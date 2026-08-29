# frozen_string_literal: true

require "test_helper"
require "bulldogger/replay"
require "json"
require "tmpdir"

class ReplayTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  FIXTURE_DIR = File.join(ROOT, "test/fixtures/minitest_red/load_path_app")
  FIXTURE_FILE = File.join(FIXTURE_DIR, "signature_test.rb")

  # Standing in for what a real test runner's boot script adds and a
  # replay child must independently forward: this directory on
  # $LOAD_PATH, exactly as Rake::TestTask's own `-Itest` does for a
  # real project (see the fixture's own comment). Only the *calling*
  # process gets this in setup; whether the replay child also gets it
  # is exactly what these tests check.
  def setup
    super
    $LOAD_PATH.unshift(FIXTURE_DIR)
  end

  def teardown
    $LOAD_PATH.delete(FIXTURE_DIR)
    super
  end

  def test_replay_forwards_the_load_path_so_the_app_method_reaches_the_trace
    result = run_replay(Bulldogger::Replay)

    assert_equal true, result[:reproduced]
    call_event, return_event = signature_events(result[:path])
    refute_nil call_event, "no call event for Signature.accepts_arity? in #{result[:path]}"
    refute_nil return_event, "no return event for Signature.accepts_arity? in #{result[:path]}"
    assert_equal({ "value" => "true" }, return_event["return"])
  end

  # Proves the assertions above have teeth. ReplayWithoutLoadPathForwarding
  # stands in for the library's own pre-fix behavior (the child
  # inherited none of the parent's $LOAD_PATH, see the class comment
  # below) -- the exact bug measured against a real gem
  # (crmne/archspec). With it, the child dies loading
  # "load_path_helper" before Signature is even defined, and the
  # resulting trace has no call/return for it. If a future change
  # broke #forwarded_load_path_flags again, this is the test that
  # would notice: it exercises the same absence a broken build would
  # produce and confirms the assertions above are actually sensitive
  # to it, not just checking that *some* trace file exists.
  def test_a_replay_child_without_load_path_forwarding_produces_a_trace_missing_the_app_method
    result = run_replay(ReplayWithoutLoadPathForwarding)

    refute_nil result[:path], "expected a trace file even though the child died on load (\"-rbulldogger/replay\" " \
                               "starts recording before the test file's own requires run)"
    call_event, return_event = signature_events(result[:path])
    assert_nil call_event, "load-path forwarding is disabled in this test; the app method should be unreachable"
    assert_nil return_event
  end

  def test_boot_replay_child_starts_a_record_session_scoped_to_the_given_run_dir
    run_dir = Dir.mktmpdir("bulldogger-replay-child-boot-test-")

    session = Bulldogger::Replay.boot_replay_child!(run_dir: run_dir)
    path = session.stop

    assert_equal run_dir, File.dirname(path)
    assert File.exist?(path)
  end

  def test_call_returns_nil_and_never_raises_when_building_the_command_blows_up
    replay = ReplayWhoseCommandRaises.new(config: Bulldogger::Config.new)

    result = replay.call(test: { framework: "minitest", id: "X#y", file: FIXTURE_FILE, line: 1 }, run_dir: Dir.mktmpdir)

    assert_nil result
  end

  private

  class ReplayWithoutLoadPathForwarding < Bulldogger::Replay
    private

    # Overrides the seam #command consults, standing in for the
    # library's pre-fix behavior. Used only to prove the acceptance
    # checks above can fail -- see the class comment on the test that
    # uses this.
    def forwarded_load_path_flags
      []
    end
  end

  class ReplayWhoseCommandRaises < Bulldogger::Replay
    private

    def command(_test)
      raise "boom: cannot build a command"
    end
  end

  def run_replay(replay_class)
    run_dir = Dir.mktmpdir("bulldogger-replay-test-")
    replay = replay_class.new(config: Bulldogger::Config.new)
    test = {
      framework: "minitest",
      id: "SignatureTest#test_accepts_arity_rejects_a_count_equal_to_required",
      file: FIXTURE_FILE,
      line: 1
    }

    replay.call(test: test, run_dir: run_dir)
  end

  def signature_events(trace_path)
    events = File.readlines(trace_path).drop(1).map { |line| JSON.parse(line) }
    call_event = events.find { |e| e["event"] == "call" && e["method"] == "Signature.accepts_arity?" }
    return_event = events.find { |e| e["event"] == "return" && e["method"] == "Signature.accepts_arity?" }
    [call_event, return_event]
  end
end
