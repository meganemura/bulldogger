# frozen_string_literal: true

require_relative "acceptance_helper"
require "minitest/autorun"

class SnapshotExtensionTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  MINITEST_FIXTURE = File.join(ROOT, "test/fixtures/minitest_rerun/rerun_test.rb")
  RSPEC_FIXTURE = File.join(ROOT, "test/fixtures/rspec_rerun/rerun_spec.rb")

  def test_minitest_seed_and_printed_command_reproduce_the_failure
    assert_rerun("ruby", MINITEST_FIXTURE, seed: 12_345)
  end

  def test_rspec_seed_and_printed_command_reproduce_the_failure
    assert_rerun("rspec", RSPEC_FIXTURE, seed: 54_321)
  end

  private

  def assert_rerun(framework_command, fixture, seed:)
    stdout, _stderr, status, output_dir = run_fixture(framework_command, fixture, "--seed", seed.to_s, env: { "BULLDOGGER_REPLAY" => "0" })
    refute status.success?
    evidence = evidence_records(output_dir).fetch(0)
    assert_equal seed, evidence["seed"]
    assert_kind_of Integer, evidence["raise_ordinal"]
    assert_match(/\A[0-9a-f]{40}\z/, evidence.dig("code_state", "git_sha"))
    command = rerun_commands_from_stdout(stdout).fetch(0)
    assert_equal evidence["rerun_command"], command

    rerun_dir = Dir.mktmpdir("bulldogger-rerun-")
    rerun_stdout, rerun_stderr, rerun_status = Open3.capture3(
      { "BULLDOGGER_OUTPUT_DIR" => rerun_dir, "BULLDOGGER_REPLAY" => "0" },
      command,
      chdir: ROOT
    )
    refute rerun_status.success?, "printed command passed:\n#{rerun_stdout}\n#{rerun_stderr}"
    assert_includes rerun_stdout + rerun_stderr, "rerun marker"
    rerun_evidence = evidence_records(rerun_dir).fetch(0)
    assert_equal evidence["raise_ordinal"], rerun_evidence["raise_ordinal"]
  end
end
