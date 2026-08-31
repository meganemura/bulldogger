# frozen_string_literal: true

require_relative "acceptance_helper"
require "minitest/autorun"

class MinitestIntegrationTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  RED_FIXTURE = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/minitest_red/red_test.rb")
  GREEN_FIXTURE = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/minitest_green/green_test.rb")
  FROZEN_FIXTURE = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/minitest_red/frozen_failure_test.rb")

  def test_red_suite_writes_evidence_for_both_kinds_of_failure
    stdout, _stderr, status, output_dir = run_fixture("ruby", RED_FIXTURE)

    refute status.success?, "the red fixture is expected to fail"

    paths = evidence_paths_from_stdout(stdout)
    assert_equal 2, paths.size, "one evidence line per failing test, in stdout:\n#{stdout}"
    paths.each { |path| assert File.exist?(path), "#{path} named in stdout but missing on disk" }

    assertion_failure = evidence_for(output_dir, "test_assertion_failure")
    deep_raise = evidence_for(output_dir, "test_deep_raise")
    refute_nil assertion_failure
    refute_nil deep_raise

    assert_seeded_locals_and_redaction(assertion_failure)
    assert_seeded_locals_and_redaction(deep_raise, at_frame_index: 0)
    assert_equal "app.rb", File.basename(deep_raise["frames"][0]["path"])
    assert_equal "capture_frames", deep_raise["capture_mode"]
    assert_includes stdout, "bulldogger evidence: #{evidence_path_for(output_dir, deep_raise)} (raising method is in these frames)"
    assert_includes stdout, "bulldogger evidence: #{evidence_path_for(output_dir, assertion_failure)} (frames do not show where the value came from)"

    # Evidence is written per-failure, independent of suite end; this
    # is the check that Bulldogger.finish (index.json) and stop both
    # actually ran for this child process.
    run_dir = run_dir_for(output_dir)
    refute_nil run_dir, "no run-* directory under #{output_dir}"
    assert File.exist?(File.join(run_dir, "index.json"))
  end

  # The reporter prints the evidence line to its own io and never
  # touches the failure exception, so a frozen exception (one that
  # can't take a singleton method) is not a special case -- this
  # fixture raises an already-frozen Minitest::Assertion directly to
  # keep that guarantee under test rather than assumed.
  def test_frozen_failure_falls_back_to_a_printed_stdout_line
    stdout, _stderr, status, output_dir = run_fixture("ruby", FROZEN_FIXTURE)

    refute status.success?, "the frozen fixture is expected to fail"

    paths = evidence_paths_from_stdout(stdout)
    assert_equal 1, paths.size, "in stdout:\n#{stdout}"
    assert File.exist?(paths.first)
    evidence = evidence_for(output_dir, "test_frozen_assertion_failure")
    refute_nil evidence
    assert_includes stdout, "bulldogger evidence: #{evidence_path_for(output_dir, evidence)} (frames do not show where the value came from)"
  end

  def test_green_suite_creates_no_run_directory
    _stdout, _stderr, status, output_dir = run_fixture("ruby", GREEN_FIXTURE)

    assert status.success?, "the green fixture is expected to pass"
    assert no_run_directory?(output_dir)
  end

  # BULLDOGGER_DISABLE means "the switch is off", not "capture came up
  # empty" -- run_fixture twice (switch off, then on) and compare the
  # deterministic parts of the summary (exit status, run/failure
  # counts) to prove the switch changes nothing about the suite's own
  # result. Timing text in stdout varies between runs and is not
  # compared.
  def test_disabled_switch_writes_nothing_and_leaves_the_suite_result_unchanged
    baseline_stdout, _stderr, baseline_status, = run_fixture("ruby", RED_FIXTURE)
    stdout, _stderr, status, output_dir = run_fixture("ruby", RED_FIXTURE, env: { "BULLDOGGER_DISABLE" => "1" })

    assert_equal baseline_status.exitstatus, status.exitstatus
    assert_equal summary_counts(baseline_stdout), summary_counts(stdout)
    assert no_run_directory?(output_dir)
    assert_empty evidence_paths_from_stdout(stdout)
  end

  # BULLDOGGER_DISABLED is the alias covered by the config unit tests;
  # this is the one place the alias is exercised end to end, through a
  # real child process rather than a Config instance.
  def test_disabled_alias_env_var_also_writes_nothing
    stdout, _stderr, status, output_dir = run_fixture("ruby", RED_FIXTURE, env: { "BULLDOGGER_DISABLED" => "1" })

    refute status.success?, "the red fixture is still expected to fail"
    assert no_run_directory?(output_dir)
    assert_empty evidence_paths_from_stdout(stdout)
  end

  def test_forced_degraded_mode_marks_frame0_only
    _stdout, _stderr, status, output_dir = run_fixture("ruby", RED_FIXTURE, env: { "BULLDOGGER_FRAME_SOURCE" => "degraded" })

    refute status.success?

    data = evidence_for(output_dir, "test_deep_raise")
    refute_nil data
    assert_equal "degraded", data["capture_mode"]
    assert data["frames"][0]["locals"], "frame 0 should carry locals in degraded mode"
    refute data["frames"][0].key?("locals_unavailable")
    assert data["frames"][1]["locals_unavailable"], "frames past 0 should be marked unavailable, not silently empty"
  end

  private

  # Minitest's own summary line ("2 runs, 1 assertions, 1 failures, 1
  # errors, 0 skips") is the one part of stdout that is both
  # deterministic and proves the suite's result: the elapsed-time text
  # around it varies run to run, so comparing full stdout would be
  # comparing noise.
  def summary_counts(stdout)
    stdout[/\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips/]
  end

  # deep_raise's seeded locals live in app.rb's Order.total frame,
  # which capture_frames places at index 0 (the raise site itself).
  # assertion_failure's seeded locals live one or two frames further
  # out, inside Minitest's own assert/assert_equal frames -- so this
  # searches every frame rather than assuming a fixed index, except
  # when the caller already knows which frame to pin (the degrade
  # case, where only frame 0 carries locals at all).
  def assert_seeded_locals_and_redaction(evidence, at_frame_index: nil)
    frames = at_frame_index ? [evidence["frames"][at_frame_index]] : evidence["frames"]
    locals = frames.filter_map { |f| f["locals"] }.reduce({}, :merge)

    assert_equal({ "value" => "3" }, locals["qty"])
    assert_equal({ "value" => "[1, 2, 3]" }, locals["rows"])
    assert_equal true, locals.dig("api_token", "redacted")
    refute locals["api_token"].key?("value")
  end
end
