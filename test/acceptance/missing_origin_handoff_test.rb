# frozen_string_literal: true

require_relative "acceptance_helper"
require "minitest/autorun"
require "json"
require "fileutils"

# Automatic replay used to answer this shape: an assertion fails after
# the producing application method has already returned, so the
# snapshot's own frames hold no trace of it. Replay is retired; the
# rerun command the failure output prints is the only handoff left,
# and this test walks it end to end: the printed command, run again
# under `bulldogger frames`, must index the producing call.
class MissingOriginHandoffTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  FIXTURE = File.join(ROOT, "test/fixtures/missing_origin/produced_value_test.rb")

  def test_the_printed_rerun_command_reaches_the_producing_call_through_frames
    stdout, _stderr, status, = run_fixture("ruby", FIXTURE)

    refute status.success?, "the fixture's own assertion is deliberately wrong"
    assert_includes stdout, "(frames do not show where the value came from)"
    command = rerun_commands_from_stdout(stdout).fetch(0)

    frames_dir = Dir.mktmpdir("bulldogger-missing-origin-frames-")
    frames_stdout, frames_stderr, = Open3.capture3(
      { "BULLDOGGER_OUTPUT_DIR" => frames_dir },
      "bundle exec ruby -Ilib exe/bulldogger frames -- #{command}",
      chdir: ROOT
    )

    frames_path = frames_stdout[/bulldogger frames: (.+\.jsonl)$/, 1]
    refute_nil frames_path, "in stdout:\n#{frames_stdout}\n#{frames_stderr}"
    records = File.readlines(frames_path, chomp: true).map { |line| JSON.parse(line) }

    assert records.any? { |record| record["type"] == "frame" && record["app"] && record["method"] == "total" },
           "no application frame for Pricing.total in #{frames_path}"
  ensure
    FileUtils.remove_entry(frames_dir) if frames_dir && Dir.exist?(frames_dir)
  end
end
