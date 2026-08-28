# frozen_string_literal: true

require "test_helper"
require "bulldogger/record"
require "json"
require "tmpdir"

# Writer's real callers (Record::Session) only ever call #write_event
# from inside a global TracePoint hook, which stdlib Coverage cannot
# reliably observe (see the task report). Writer takes no TracePoint
# object itself, though -- #write_event's argument is a plain Hash --
# so it is fully testable on its own, outside any hook.
class RecordWriterTest < Minitest::Test
  def test_write_event_appends_one_json_line_per_call
    Dir.mktmpdir("bulldogger-writer-test-") do |run_dir|
      writer = Bulldogger::Record::Writer.new(run_dir: run_dir, header: { "schema_version" => 1 })

      writer.write_event({ "event" => "call", "seq" => 1 })
      writer.write_event({ "event" => "return", "seq" => 2 })
      path = writer.close

      lines = File.readlines(path).map { |line| JSON.parse(line) }
      assert_equal [{ "schema_version" => 1 }, { "event" => "call", "seq" => 1 }, { "event" => "return", "seq" => 2 }],
                   lines
    end
  end

  def test_reserve_path_numbers_a_second_trace_after_the_first
    Dir.mktmpdir("bulldogger-writer-test-") do |run_dir|
      first = Bulldogger::Record::Writer.new(run_dir: run_dir, header: {})
      first.close
      second = Bulldogger::Record::Writer.new(run_dir: run_dir, header: {})

      assert_equal "trace-001.jsonl", File.basename(first.path)
      assert_equal "trace-002.jsonl", File.basename(second.path)
    end
  end
end
