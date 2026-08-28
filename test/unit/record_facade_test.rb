# frozen_string_literal: true

require "test_helper"
require "bulldogger"
require "json"

# Bulldogger.record/#record_start/#trace_to_sqlite are the entry points
# an app reaches after a plain `require "bulldogger"`. Their bodies
# delegate to Bulldogger::Record, so what these tests pin is the
# reachability itself: for a while probe had facade methods and record
# did not, and record was usable only by requiring an inner file.
class RecordFacadeTest < Minitest::Test
  def test_record_traces_the_block_and_returns_the_written_path
    path = Bulldogger.record { helper_call(2) }

    assert File.absolute_path?(path)
    methods = events(path).map { |e| e["method"] }
    assert_includes methods, "RecordFacadeTest#helper_call"
  end

  def test_record_start_returns_a_session_whose_stop_writes_the_trace
    session = Bulldogger.record_start
    helper_call(3)
    path = session.stop

    assert File.exist?(path)
    assert_includes events(path).map { |e| e["method"] }, "RecordFacadeTest#helper_call"
  end

  def test_trace_to_sqlite_returns_nil_when_sqlite3_is_absent
    path = Bulldogger.record { helper_call(4) }

    result = nil
    _out, err = capture_io { result = Bulldogger.trace_to_sqlite(path, "unused.db") }

    assert_nil result
    assert_match(/sqlite3 not available/, err)
  end

  # TracePoint#enable is defined in Ruby's <internal:trace_point>, not
  # under this library's lib/, so the path filter that keeps
  # bulldogger's own frames out of a trace did not catch it. From the
  # second session in a process onward the mechanism is already armed
  # when this session enables it, so its own enable returned into a
  # live trace and wrote an event the app never made. One session
  # cannot show this; the second is the whole point of the test.
  def test_a_second_session_records_no_phantom_tracepoint_event
    first = Bulldogger.record { helper_call(5) }
    second = Bulldogger.record { helper_call(6) }

    assert_equal events(first).length, events(second).length
    second_methods = events(second).map { |e| e["method"] }
    refute_includes second_methods, "TracePoint#enable"
    assert_equal %w[RecordFacadeTest#helper_call RecordFacadeTest#helper_call], second_methods
  end

  private

  def helper_call(value)
    value * 2
  end

  def events(path)
    File.readlines(path).drop(1).map { |line| JSON.parse(line) }
  end
end
