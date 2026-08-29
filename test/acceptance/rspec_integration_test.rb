# frozen_string_literal: true

require_relative "acceptance_helper"
require "minitest/autorun"

class RSpecIntegrationTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  RED_FIXTURE = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/rspec_red/red_spec.rb")
  GREEN_FIXTURE = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/rspec_green/green_spec.rb")
  FROZEN_FIXTURE = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/rspec_red/frozen_failure_spec.rb")

  def test_red_suite_writes_evidence_for_both_kinds_of_failure
    stdout, _stderr, status, output_dir = run_fixture("rspec", RED_FIXTURE)

    refute status.success?, "the red fixture is expected to fail"

    paths = evidence_paths_from_stdout(stdout)
    assert_equal 2, paths.size, "one evidence line per failing example, in stdout:\n#{stdout}"
    paths.each { |path| assert File.exist?(path), "#{path} named in stdout but missing on disk" }
    replay_paths = replay_paths_from_stdout(stdout)
    assert_equal 1, replay_paths.size
    assert File.exist?(replay_paths.first)

    assertion_failure = evidence_for(output_dir, "computes the total")
    deep_raise = evidence_for(output_dir, "raises deep in app code")
    refute_nil assertion_failure
    refute_nil deep_raise

    # rspec-expectations raises from inside its own library, several
    # frames below the example: measured at 9 frames before the
    # example's own frame, well inside the default max_frames of 20,
    # so the seeded locals are not omitted here.
    assert_seeded_locals_and_redaction(assertion_failure)
    assert_seeded_locals_and_redaction(deep_raise, at_frame_index: 0)
    assert_equal "app.rb", File.basename(deep_raise["frames"][0]["path"])
    assert_equal "capture_frames", deep_raise["capture_mode"]
    replay_evidence = [assertion_failure, deep_raise].find { |record| record["replay"] }
    assert_equal replay_paths.first, replay_evidence["replay"]
    assert_equal true, replay_evidence["replay_reproduced"]
    evidence_without_replay = [assertion_failure, deep_raise].find { |record| !record["replay"] }
    assert_includes stdout, "bulldogger replay: #{replay_evidence["replay"]} (value was produced before the assertion raised)"
    assert_includes stdout, "bulldogger evidence: #{evidence_path_for(output_dir, evidence_without_replay)} (raising method is in these frames)"

    # Evidence is written per-failure, independent of suite end; this
    # is the check that Bulldogger.finish (index.json) and stop both
    # actually ran for this child process.
    run_dir = run_dir_for(output_dir)
    refute_nil run_dir, "no run-* directory under #{output_dir}"
    assert File.exist?(File.join(run_dir, "index.json"))
  end

  # Mirrors MinitestIntegrationTest's own frozen-fallback check: a
  # regular red-suite failure never reaches the fallback branch (a
  # `raise` or a failed `expect` builds a fresh, unfrozen exception),
  # so exercising it needs its own fixture that raises an
  # already-frozen exception directly.
  def test_frozen_failure_falls_back_to_a_printed_stdout_line
    stdout, _stderr, status, output_dir = run_fixture("rspec", FROZEN_FIXTURE)

    refute status.success?, "the frozen fixture is expected to fail"

    paths = evidence_paths_from_stdout(stdout)
    assert_equal 1, paths.size, "in stdout:\n#{stdout}"
    assert File.exist?(paths.first)
    evidence = evidence_for(output_dir, "raises an already-frozen exception")
    refute_nil evidence
    assert_includes stdout, "bulldogger replay: #{evidence["replay"]} (value was produced before the assertion raised)"
  end

  def test_green_suite_creates_no_run_directory
    _stdout, _stderr, status, output_dir = run_fixture("rspec", GREEN_FIXTURE)

    assert status.success?, "the green fixture is expected to pass"
    assert no_run_directory?(output_dir)
  end

  # BULLDOGGER_DISABLE means "the switch is off", not "capture came up
  # empty" -- run_fixture twice (switch off, then on) and compare the
  # deterministic parts of the summary (exit status, example/failure
  # counts) to prove the switch changes nothing about the suite's own
  # result. Timing text in stdout varies between runs and is not
  # compared.
  def test_disabled_switch_writes_nothing_and_leaves_the_suite_result_unchanged
    baseline_stdout, _stderr, baseline_status, = run_fixture("rspec", RED_FIXTURE)
    stdout, _stderr, status, output_dir = run_fixture("rspec", RED_FIXTURE, env: { "BULLDOGGER_DISABLE" => "1" })

    assert_equal baseline_status.exitstatus, status.exitstatus
    assert_equal summary_counts(baseline_stdout), summary_counts(stdout)
    assert no_run_directory?(output_dir)
    assert_empty evidence_paths_from_stdout(stdout)
  end

  # BULLDOGGER_DISABLED is the alias covered by the config unit tests;
  # this is the one place the alias is exercised end to end, through a
  # real child process rather than a Config instance.
  def test_disabled_alias_env_var_also_writes_nothing
    stdout, _stderr, status, output_dir = run_fixture("rspec", RED_FIXTURE, env: { "BULLDOGGER_DISABLED" => "1" })

    refute status.success?, "the red fixture is still expected to fail"
    assert no_run_directory?(output_dir)
    assert_empty evidence_paths_from_stdout(stdout)
  end

  def test_forced_degraded_mode_marks_frame0_only
    _stdout, _stderr, status, output_dir = run_fixture("rspec", RED_FIXTURE, env: { "BULLDOGGER_FRAME_SOURCE" => "degraded" })

    refute status.success?

    data = evidence_for(output_dir, "raises deep in app code")
    refute_nil data
    assert_equal "degraded", data["capture_mode"]
    assert data["frames"][0]["locals"], "frame 0 should carry locals in degraded mode"
    refute data["frames"][0].key?("locals_unavailable")
    assert data["frames"][1]["locals_unavailable"], "frames past 0 should be marked unavailable, not silently empty"
  end

  private

  # RSpec's own summary line ("2 examples, 2 failures") is the one
  # part of stdout that is both deterministic and proves the suite's
  # result: the elapsed-time text around it varies run to run, so
  # comparing full stdout would be comparing noise.
  def summary_counts(stdout)
    stdout[/\d+ examples?, \d+ failures?/]
  end

  def assert_seeded_locals_and_redaction(evidence, at_frame_index: nil)
    frames = at_frame_index ? [evidence["frames"][at_frame_index]] : evidence["frames"]
    locals = frames.filter_map { |f| f["locals"] }.reduce({}, :merge)

    assert_equal({ "value" => "3" }, locals["qty"])
    assert_equal({ "value" => "[1, 2, 3]" }, locals["rows"])
    assert_equal true, locals.dig("api_token", "redacted")
    refute locals["api_token"].key?("value")
  end
end
