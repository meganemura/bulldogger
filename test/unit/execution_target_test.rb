# frozen_string_literal: true

require "test_helper"
require "bulldogger/execution_target"
require "json"
require "stringio"
require "tmpdir"

# index_state_matches?, addressable?, and frame_record are all
# private_class_method + module_function, reached only through
# ExecutionTarget.acceptable? in production. The tests below reach
# error paths the acceptance suite's acceptable? calls left
# uncovered (confirmed by the coverage gate): an unreadable index
# file (hit twice, once through each of the two rescue clauses), a
# block frame whose parent chain never reaches an application call,
# and a fid absent from an index that otherwise reads fine.
class ExecutionTargetTest < Minitest::Test
  def test_index_state_matches_reports_an_unreadable_index_file
    Dir.mktmpdir("bulldogger-execution-target-") do |dir|
      missing_index = File.join(dir, "missing.jsonl")
      stderr = StringIO.new

      result = Bulldogger::ExecutionTarget.send(:index_state_matches?, missing_index, { "git_sha" => "x" }, "flt", stderr)

      refute result
      assert_includes stderr.string, "cannot read index #{missing_index}"
    end
  end

  def test_addressable_reports_no_ancestor_when_the_block_frame_has_no_parent
    Dir.mktmpdir("bulldogger-execution-target-") do |dir|
      index = File.join(dir, "frames.jsonl")
      fid = "#{dir}/app.rb:each#1"
      File.write(index, "#{JSON.generate('type' => 'frame', 'fid' => fid, 'event' => 'b_call')}\n")
      stderr = StringIO.new

      result = Bulldogger::ExecutionTarget.send(:addressable?, fid, index, "flt", stderr)

      refute result
      assert_includes stderr.string, "is a block frame"
      assert_includes stderr.string, "no addressable ancestor was recorded for it; use probe instead"
    end
  end

  def test_addressable_treats_an_unreadable_index_as_already_reported
    Dir.mktmpdir("bulldogger-execution-target-") do |dir|
      missing_index = File.join(dir, "missing.jsonl")
      stderr = StringIO.new

      result = Bulldogger::ExecutionTarget.send(:addressable?, "x.rb:m#1", missing_index, "flt", stderr)

      assert result
      assert_empty stderr.string
    end
  end

  def test_frame_record_returns_nil_when_no_record_matches_the_fid
    Dir.mktmpdir("bulldogger-execution-target-") do |dir|
      index = File.join(dir, "frames.jsonl")
      other_fid = "#{dir}/app.rb:other#1"
      File.write(index, "#{JSON.generate('type' => 'frame', 'fid' => other_fid, 'event' => 'call')}\n")

      result = Bulldogger::ExecutionTarget.send(:frame_record, index, "#{dir}/app.rb:target#1")

      assert_nil result
    end
  end
end
