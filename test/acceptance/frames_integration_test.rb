# frozen_string_literal: true

require_relative "acceptance_helper"
require "fileutils"
require "minitest/autorun"

class FramesIntegrationTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  def test_minitest_frames_include_calls_raises_and_envelope
    command = ["bundle", "exec", "ruby", "-Itest", "test/fixtures/frames/minitest_frames_test.rb", "--seed", "12345"]
    stdout, stderr, status, output_dir = run_frames(*command)

    assert status.success?, stderr
    path = frames_path(stdout)
    records = read_json_lines(path)
    frames = records.select { |record| record["type"] == "frame" }
    raises = records.select { |record| record["type"] == "raise" }
    envelope = records.find { |record| record["type"] == "envelope" }

    target = frames.find { |frame| frame["method"] == "outer" }
    child = frames.find { |frame| frame["method"] == "rescued" }
    refute_nil target
    assert_equal target["fid"], child["parent"]
    assert frames.any? { |frame| frame["app"] == false }
    assert raises.any? { |event| event["exception_class"] == "RuntimeError" && event["raise_ordinal"] == 1 }
    assert_equal command, envelope["command"]
    assert_equal 12345, envelope["seed"]
    assert_equal 0, envelope["exit_status"]
    assert envelope["code_state"].key?("git_sha")
    assert_operator envelope["outside_window_events"], :>, 0
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_rspec_frames_include_the_application_method
    command = ["bundle", "exec", "rspec", "test/fixtures/frames/rspec_frames_spec.rb", "--seed", "12345"]
    stdout, stderr, status, output_dir = run_frames(*command)

    assert status.success?, stderr
    records = read_json_lines(frames_path(stdout))
    assert records.any? { |record| record["type"] == "frame" && record["method"] == "rspec_target" }
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_application_fids_are_stable_across_runs
    command = ["bundle", "exec", "ruby", "-Itest", "test/fixtures/frames/minitest_frames_test.rb", "--seed", "12345"]
    first_stdout, _first_stderr, first_status, first_dir = run_frames(*command)
    second_stdout, _second_stderr, second_status, second_dir = run_frames(*command)

    assert first_status.success?
    assert second_status.success?
    assert_equal app_fids(frames_path(first_stdout)), app_fids(frames_path(second_stdout))
  ensure
    [first_dir, second_dir].compact.each { |dir| FileUtils.remove_entry(dir) if Dir.exist?(dir) }
  end

  def test_grandchild_records_do_not_enter_the_target_index
    command = ["bundle", "exec", "ruby", "-Itest", "test/fixtures/frames/spawn_test.rb", "--seed", "12345"]
    stdout, stderr, status, output_dir = run_frames(*command)

    assert status.success?, stderr
    records = read_json_lines(frames_path(stdout))
    refute records.any? { |record| record["method"] == "grandchild_only" }
    assert_operator Dir.glob(File.join(output_dir, "frames-*.jsonl")).length, :>=, 1
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_collector_is_a_no_op_without_the_output_gate
    collector = File.join(ROOT, "lib/bulldogger/frames_collector.rb")
    script = "require #{collector.dump}; puts TracePoint.stat[:enabled]"
    plain, plain_error, plain_status = Open3.capture3("bundle", "exec", "ruby", "-e", "puts TracePoint.stat[:enabled]", chdir: ROOT)
    loaded, loaded_error, loaded_status = Open3.capture3({ "BULLDOGGER_FRAMES_OUT" => nil }, "bundle", "exec", "ruby", "-e", script, chdir: ROOT)

    assert plain_status.success?, plain_error
    assert loaded_status.success?, loaded_error
    assert_equal plain, loaded
  end

  private

  def run_frames(*command)
    output_dir = Dir.mktmpdir("bulldogger-frames-")
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "frames", "--", *command, chdir: ROOT)
    [stdout, stderr, status, output_dir]
  end

  def frames_path(stdout)
    stdout[/bulldogger frames: (.+\.jsonl)$/, 1]
  end

  def read_json_lines(path)
    File.readlines(path, chomp: true).map { |line| JSON.parse(line) }
  end

  def app_fids(path)
    read_json_lines(path).filter_map { |record| record["fid"] if record["type"] == "frame" && record["app"] }.sort
  end
end
