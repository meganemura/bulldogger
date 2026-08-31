# frozen_string_literal: true

require_relative "acceptance_helper"
require "fileutils"
require "minitest/autorun"

class FltIntegrationTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  def test_differential_records_reconstruct_visible_locals_and_scope_exit
    records, stderr, status, output_dir = run_flt("branchy#1")
    assert status.success?, stderr

    call = records.find { |record| record["type"] == "call" }
    state = call.fetch("locals").dup
    states = records.filter_map do |record|
      next unless record["type"] == "line"

      record.fetch("out_of_scope", []).each { |name| state.delete(name) }
      state.merge!(record.fetch("new", {}))
      record.fetch("changed", {}).each { |name, change| state[name] = change.fetch("new") }
      [record.fetch("lineno"), state.dup]
    end

    redacted = { "value" => "[REDACTED]" }
    expected = [
      [9, { "input" => { "value" => "1" }, "password" => redacted, "total" => { "value" => "1" }, "label" => { "value" => "nil" } }],
      [10, { "input" => { "value" => "1" }, "password" => redacted, "total" => { "value" => "1" }, "label" => { "value" => "nil" }, "increment" => { "value" => "2" }, "block_value" => { "value" => "nil" } }],
      [11, { "input" => { "value" => "1" }, "password" => redacted, "total" => { "value" => "1" }, "label" => { "value" => "nil" }, "increment" => { "value" => "2" }, "block_value" => { "value" => "3" } }],
      [13, { "input" => { "value" => "1" }, "password" => redacted, "total" => { "value" => "3" }, "label" => { "value" => "nil" } }],
      [14, { "input" => { "value" => "1" }, "password" => redacted, "total" => { "value" => "3" }, "label" => { "value" => "\"large\"" } }]
    ]
    assert_equal expected, states
    assert_equal "[3, \"large\", \"hidden\"]", records.find { |record| record["type"] == "return" }.fetch("value").fetch("value")
    assert_equal({ "input" => { "value" => "1" }, "password" => { "value" => "[REDACTED]" } }, call.fetch("args"))
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_call_index_selects_the_second_invocation
    records, stderr, status, output_dir = run_flt("repeated#2")
    assert status.success?, stderr
    assert_equal({ "value" => { "value" => "9" } }, records.find { |record| record["type"] == "call" }.fetch("args"))
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_loop_keeps_first_and_last_values_and_marks_skipped_iterations
    records, stderr, status, output_dir = run_flt("loops#1")
    assert status.success?, stderr
    marker = records.find { |record| record["type"] == "skipped_iterations" }
    assert_equal 2, marker.fetch("count")
    values = records.filter_map { |record| record.dig("changed", "index", "new", "value") }
    assert_includes values, "0"
    assert_includes values, "4"
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_each_loop_is_folded
    records, stderr, status, output_dir = run_flt("each_loop#1")
    assert status.success?, stderr
    assert_equal 2, records.find { |record| record["type"] == "skipped_iterations" }.fetch("count")
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_nested_loops_keep_independent_fold_accounts
    records, stderr, status, output_dir = run_flt("nested_loops#1")
    assert status.success?, stderr
    counts = records.filter_map { |record| record["count"] if record["type"] == "skipped_iterations" }
    assert_operator counts.count(2), :>=, 2
    assert_includes counts, 1
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_non_application_target_names_safe_alternatives
    output_dir = Dir.mktmpdir("bulldogger-flt-")
    command = ["bundle", "exec", "ruby", "-e", "exit 0"]
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    _stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "flt", "/tmp/gem.rb:work#1", "--", *command, chdir: ROOT)
    refute status.success?
    assert_includes stderr, "frames index"
    assert_includes stderr, "gem source"
    assert_includes stderr, "probe"
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  # branchy's own [2].each block keeps "branchy" as its method_id (it
  # sits inside a def), so its fid ("branchy#2") looks like an ordinary
  # call by pattern alone -- flt must tell the two apart from the
  # index's "event" field and name branchy#1, the call that encloses it.
  def test_block_target_refuses_and_names_its_ancestor
    output_dir = Dir.mktmpdir("bulldogger-flt-")
    path = File.expand_path("../fixtures/flt/minitest_flt_test.rb", __dir__)
    index = generate_index(output_dir, path)
    command = ["bundle", "exec", "ruby", "-e", "abort 'must not run'"]
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    _stdout, stderr, status = Open3.capture3(
      env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "flt", "#{path}:branchy#2", "--index", index, "--", *command, chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "'#{path}:branchy#2' is a block frame"
    assert_includes stderr, "'#{path}:branchy#1'"
    refute_includes stderr, "must not run"
  ensure
    FileUtils.remove_entry(output_dir) if output_dir && Dir.exist?(output_dir)
  end

  def test_index_code_state_mismatch_prints_both_markers
    output_dir = Dir.mktmpdir("bulldogger-flt-")
    index = File.join(output_dir, "frames.jsonl")
    File.write(index, JSON.generate("type" => "envelope", "code_state" => { "git_sha" => "old", "dirty_digest" => "old-dirty" }) + "\n")
    path = File.expand_path("../fixtures/flt/minitest_flt_test.rb", __dir__)
    command = ["bundle", "exec", "ruby", "-e", "abort 'must not run'"]
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    _stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "flt", "#{path}:branchy#1", "--index", index, "--", *command, chdir: ROOT)
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
      env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "frames", "--", "bundle", "exec", "ruby", "-Itest", path, "--seed", "12345", chdir: ROOT
    )
    raise "frames generation failed: #{stderr}" unless status.success?

    stdout[/bulldogger frames: (.+\.jsonl)$/, 1]
  end

  def run_flt(method)
    output_dir = Dir.mktmpdir("bulldogger-flt-")
    path = File.expand_path("../fixtures/flt/minitest_flt_test.rb", __dir__)
    fid = "#{path}:#{method}"
    command = ["bundle", "exec", "ruby", "-Itest", path, "--seed", "12345"]
    env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-Ilib", "exe/bulldogger", "flt", fid, "--", *command, chdir: ROOT)
    trace_path = stdout[/bulldogger flt: (.+\.jsonl)$/, 1]
    records = trace_path && File.readlines(trace_path, chomp: true).map { |line| JSON.parse(line) }
    [records || [], stderr, status, output_dir]
  end
end
