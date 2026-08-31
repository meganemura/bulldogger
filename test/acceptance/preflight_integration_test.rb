# frozen_string_literal: true

require_relative "acceptance_helper"
require "fileutils"
require "minitest/autorun"

class PreflightIntegrationTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  def test_deterministic_run_exits_zero
    command = ["bundle", "exec", "ruby", "-Itest", "test/fixtures/frames/minitest_frames_test.rb", "--seed", "12345"]
    stdout, stderr, status, output_dir = run_preflight(*command)

    assert status.success?, stderr
    assert_match(/deterministic/, stdout)
    assert_match(/app frames: \d+/, stdout)
    assert_equal 2, stdout.scan(%r{/frames-\d+\.jsonl}).length
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_unstable_run_reports_the_first_divergence
    command = ["bundle", "exec", "ruby", "-Itest", "test/fixtures/frames/unstable_frames_test.rb", "--seed", "12345"]
    stdout, _stderr, status, output_dir = run_preflight(*command)

    assert_equal 1, status.exitstatus
    assert_match(/first divergence at event \d+/, stdout)
    assert_match(/first: \(call, .+:\d+, stable_branch\)/, stdout)
    assert_match(/second: \(call, .+:\d+, alternate_branch\)/, stdout)
    assert_match(/app frames: \d+ and \d+/, stdout)
    assert_match(/not eligible for bulldogger re-execution/, stdout)
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_missing_command_exits_two
    _stdout, stderr, status, output_dir = run_preflight("bulldogger-command-that-does-not-exist")

    assert_equal 2, status.exitstatus
    assert_match(/failed to start/, stderr)
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_command_without_frame_collection_exits_two
    _stdout, stderr, status, output_dir = run_preflight("/usr/bin/false")

    assert_equal 2, status.exitstatus
    assert_match(/failed to start or collect/, stderr)
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  private

  def run_preflight(*command)
    output_dir = Dir.mktmpdir("bulldogger-preflight-")
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "preflight", "--", *command, chdir: ROOT)
    [stdout, stderr, status, output_dir]
  end
end
