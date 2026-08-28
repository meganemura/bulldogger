# frozen_string_literal: true

require "test_helper"
require "bulldogger/record"
require "json"

class RecordSqliteTest < Minitest::Test
  FAKE_SQLITE3_LIB = File.expand_path("../fixtures/record/fake_sqlite3", __dir__)

  # sqlite3 is genuinely not installed in this environment (verified
  # while building this task, inside and outside the bundle) and
  # cannot be added -- AGENTS.md requires the owner's approval for any
  # new dependency, and contract-verbs.md is explicit that sqlite3
  # stays a soft require, never a gemspec entry. So this needs no
  # stubbing at all: `require "sqlite3"` fails here on its own.
  def test_returns_nil_when_sqlite3_is_unavailable
    result = nil
    _out, err = capture_io { result = Bulldogger::Record::SqliteConverter.convert("whatever.jsonl", "whatever.db") }

    assert_nil result
    # "使えないことを明示的に伝えて nil を返す" -- nil alone is not
    # enough; this is the explicit signal the contract requires,
    # unconditional (not gated behind BULLDOGGER_DEBUG).
    assert_match(/sqlite3 not available/, err)
    assert_match(/LoadError/, err)
  end

  def test_creates_one_row_per_event_line_matching_the_jsonl_count
    jsonl_path = write_sample_jsonl
    db_path = File.join(File.dirname(jsonl_path), "trace.db")

    with_fake_sqlite3 do
      result = Bulldogger::Record::SqliteConverter.convert(jsonl_path, db_path)

      assert_equal db_path, result
      rows = JSON.parse(File.read(db_path))
      event_line_count = File.readlines(jsonl_path).size - 1 # minus the header line
      assert_equal event_line_count, rows.size
      assert_includes rows.map { |r| r["event"] }, "call"
    end
  end

  private

  def write_sample_jsonl
    path = Bulldogger::Record.run { plain_return(1) }
    refute_nil path, "setup: recording must be enabled for this test to produce a JSONL file"
    path
  end

  def plain_return(qty, rows = [1, 2, 3])
    rows.length
    qty
  end

  def with_fake_sqlite3
    $LOAD_PATH.unshift(FAKE_SQLITE3_LIB)
    yield
  ensure
    $LOAD_PATH.delete(FAKE_SQLITE3_LIB)
    Object.send(:remove_const, :SQLite3) if Object.const_defined?(:SQLite3)
  end
end
