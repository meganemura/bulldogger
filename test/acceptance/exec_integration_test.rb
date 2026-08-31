# frozen_string_literal: true

require_relative "acceptance_helper"
require "fileutils"
require "minitest/autorun"

class ExecIntegrationTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  def test_local_variable_injection_turns_a_failing_test_green
    records, stdout, stderr, status, output_dir = run_exec(
      "threshold#1", line: 9, statement: "binding.local_variable_set(:result, 10)", test_name: "test_injection_can_change_the_outcome"
    )

    assert status.success?, stderr
    assert_includes stdout, "bulldogger value: 10"
    assert_includes stdout, "bulldogger result: pass"
    result = records.find { |record| record["type"] == "result" }
    assert_equal "pass", result.fetch("outcome")
    assert_equal({ "value" => "10" }, result.fetch("value"))
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end


  def test_address_without_launch_token_cannot_inject
    output_dir = Dir.mktmpdir("bulldogger-exec-")
    path = File.expand_path("../fixtures/exec/minitest_exec_test.rb", __dir__)
    collector = File.expand_path("../../lib/bulldogger/exec_collector.rb", __dir__)
    base_path = File.join(output_dir, "exec")
    env = {
      "BULLDOGGER_EXEC_OUT" => base_path,
      "BULLDOGGER_EXEC_FID" => "#{path}:threshold#1",
      "BULLDOGGER_EXEC_LINE" => "9",
      "BULLDOGGER_EXEC_VISIT" => "1",
      "BULLDOGGER_EXEC_STATEMENT" => "binding.local_variable_set(:result, 10)",
      "RUBYOPT" => "-r#{collector}"
    }
    _stdout, stderr, status = Open3.capture3(
      env, "bundle", "exec", "ruby", "-Itest", path, "-n", "test_injection_can_change_the_outcome", chdir: ROOT
    )

    refute status.success?, stderr
    assert_empty Dir.glob("#{base_path}-*.jsonl")
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_third_line_visit_records_the_third_value
    records, _stdout, stderr, status, output_dir = run_exec(
      "loop_values#1", line: 16, visit: 3, statement: "current", test_name: "test_loop_values"
    )

    assert status.success?, stderr
    assert_equal({ "value" => "3" }, records.find { |record| record["type"] == "result" }.fetch("value"))
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_statement_exception_is_recorded_without_changing_the_test_outcome
    path = File.expand_path("../fixtures/exec/minitest_exec_test.rb", __dir__)
    _control_stdout, control_stderr, control_status = Open3.capture3(
      "bundle", "exec", "ruby", "-Itest", path, "-n", "test_statement_exception_does_not_change_the_outcome", chdir: ROOT
    )
    records, _stdout, stderr, status, output_dir = run_exec(
      "stable_value#1", line: 23, statement: "raise 'injected'", test_name: "test_statement_exception_does_not_change_the_outcome"
    )

    assert control_status.success?, control_stderr
    assert_equal control_status.exitstatus, status.exitstatus
    assert status.success?, stderr
    result = records.find { |record| record["type"] == "result" }
    assert_equal "RuntimeError", result.fetch("exception_class")
    assert_equal({ "value" => "\"injected\"" }, result.fetch("message"))
    assert_equal "pass", result.fetch("outcome")
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_result_values_use_redaction
    records, _stdout, stderr, status, output_dir = run_exec(
      "secret_value#1", line: 28, statement: "secret", test_name: "test_redaction"
    )

    assert status.success?, stderr
    value = records.find { |record| record["type"] == "result" }.dig("value", "value")
    assert_equal "{:password => \"[REDACTED]\", :visible => \"shown\"}", value
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_non_application_target_uses_the_shared_refusal
    output_dir = Dir.mktmpdir("bulldogger-exec-")
    command = ["bundle", "exec", "ruby", "-e", "exit 0"]
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    _stdout, stderr, status = Open3.capture3(
      env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "exec", "/tmp/gem.rb:work#1",
      "--line", "1", "--statement", "nil", "--", *command, chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "target is not an application frame; use the frames index, read the gem source, or use probe"
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  # loop_values' own 3.times block keeps "loop_values" as its
  # method_id (it sits inside a def), so its fid ("loop_values#2")
  # looks like an ordinary call by pattern alone -- exec must tell the
  # two apart from the index's "event" field and name loop_values#1,
  # the call that encloses it.
  def test_block_target_refuses_and_names_its_ancestor
    output_dir = Dir.mktmpdir("bulldogger-exec-")
    path = File.expand_path("../fixtures/exec/minitest_exec_test.rb", __dir__)
    index = generate_index(output_dir, path)
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    _stdout, stderr, status = Open3.capture3(
      env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "exec", "#{path}:loop_values#2",
      "--line", "1", "--statement", "nil", "--index", index, "--", "bundle", "exec", "ruby", "-e", "abort 'must not run'", chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "'#{path}:loop_values#2' is a block frame"
    assert_includes stderr, "'#{path}:loop_values#1'"
    refute_includes stderr, "must not run"
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_index_code_state_mismatch_uses_the_shared_refusal
    output_dir = Dir.mktmpdir("bulldogger-exec-")
    index = File.join(output_dir, "frames.jsonl")
    File.write(index, JSON.generate("type" => "envelope", "code_state" => { "git_sha" => "old", "dirty_digest" => "old-dirty" }) + "\n")
    path = File.expand_path("../fixtures/exec/minitest_exec_test.rb", __dir__)
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    _stdout, stderr, status = Open3.capture3(
      env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "exec", "#{path}:threshold#1",
      "--line", "9", "--statement", "nil", "--index", index, "--", "bundle", "exec", "ruby", "-e", "abort 'must not run'", chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "index git_sha=\"old\" dirty_digest=\"old-dirty\""
    assert_match(/run git_sha=.+ dirty_digest=.+/, stderr)
    refute_includes stderr, "must not run"
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  private

  def generate_index(output_dir, path)
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    stdout, stderr, status = Open3.capture3(
      env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "frames", "--",
      "bundle", "exec", "ruby", "-Itest", path, "--seed", "12345", "-n", "test_loop_values", chdir: ROOT
    )
    raise "frames generation failed: #{stderr}" unless status.success?

    stdout[/bulldogger frames: (.+\.jsonl)$/, 1]
  end

  def run_exec(method, line:, statement:, test_name:, visit: nil)
    output_dir = Dir.mktmpdir("bulldogger-exec-")
    path = File.expand_path("../fixtures/exec/minitest_exec_test.rb", __dir__)
    arguments = ["exec", "#{path}:#{method}", "--line", line.to_s]
    arguments.concat(["--visit", visit.to_s]) if visit
    arguments.concat(["--statement", statement, "--", "bundle", "exec", "ruby", "-Itest", path, "--seed", "12345", "-n", test_name])
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", *arguments, chdir: ROOT)
    result_path = stdout[/bulldogger exec: (.+\.jsonl)$/, 1]
    records = result_path && File.readlines(result_path, chomp: true).map { |line_record| JSON.parse(line_record) }
    [records || [], stdout, stderr, status, output_dir]
  end
end
