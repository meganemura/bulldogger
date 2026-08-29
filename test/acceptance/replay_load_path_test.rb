# frozen_string_literal: true

require_relative "acceptance_helper"
require "minitest/autorun"
require "json"

# Bulldogger's own existing red fixtures never exercised replay's real
# bug: neither of red_test.rb's/red_spec.rb's two failures needs
# anything beyond require_relative, so a replay child inheriting none
# of the parent's $LOAD_PATH never showed up as a missing require.
# These fixtures add the one structural feature that did trigger it in
# a real gem (crmne/archspec): a helper found only through $LOAD_PATH,
# not through require_relative. The acceptance suite passes that -I
# flag to the outer process by hand here, the same way a real
# project's Rakefile does.
class ReplayLoadPathTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  MINITEST_DIR = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/minitest_red/load_path_app")
  MINITEST_FIXTURE = File.join(MINITEST_DIR, "signature_test.rb")
  RSPEC_DIR = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/rspec_red/load_path_app")
  RSPEC_FIXTURE = File.join(RSPEC_DIR, "signature_spec.rb")

  def test_minitest_replay_forwards_the_parents_load_path_so_the_app_method_reaches_the_trace
    stdout, _stderr, status, output_dir = run_fixture("ruby", "-I#{MINITEST_DIR}", MINITEST_FIXTURE)

    refute status.success?, "the fixture's own assertion is deliberately wrong"
    assert_signature_call_and_return_in_replay(stdout)

    evidence = evidence_for(output_dir, "test_accepts_arity_rejects_a_count_equal_to_required")
    assert_equal true, evidence["replay_reproduced"]
  end

  def test_rspec_replay_forwards_the_parents_load_path_so_the_app_method_reaches_the_trace
    stdout, _stderr, status, output_dir = run_fixture("rspec", "-I#{RSPEC_DIR}", RSPEC_FIXTURE)

    refute status.success?, "the fixture's own expectation is deliberately wrong"
    assert_signature_call_and_return_in_replay(stdout)

    evidence = evidence_for(output_dir, "rejects a count equal to required")
    assert_equal true, evidence["replay_reproduced"]
  end

  private

  # The check this task exists to strengthen: not "a replay key
  # exists" (evidence["replay"] alone), but "the fixture's own
  # application method -- the thing an agent is trying to find --
  # actually made it into the trace". A trace with only boot events
  # (Kernel#require, Bundler internals) would still have a replay key
  # and still pass a presence-only check, which is exactly how this
  # bug shipped through 17 green runs.
  def assert_signature_call_and_return_in_replay(stdout)
    replay_paths = replay_paths_from_stdout(stdout)
    assert_equal 1, replay_paths.size, "in stdout:\n#{stdout}"
    assert File.exist?(replay_paths.first)

    events = File.readlines(replay_paths.first).drop(1).map { |line| JSON.parse(line) }
    call_event = events.find { |e| e["event"] == "call" && e["method"] == "Signature.accepts_arity?" }
    return_event = events.find { |e| e["event"] == "return" && e["method"] == "Signature.accepts_arity?" }

    refute_nil call_event, "no call event for Signature.accepts_arity? in #{replay_paths.first}"
    refute_nil return_event, "no return event for Signature.accepts_arity? in #{replay_paths.first}"
    assert_equal({ "value" => "1" }, call_event.dig("args", "required"))
    assert_equal({ "value" => "1" }, call_event.dig("args", "given"))
    assert_equal({ "value" => "true" }, return_event["return"])
  end
end
