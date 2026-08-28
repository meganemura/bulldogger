# frozen_string_literal: true

require "json"

# A minimal stand-in for the sqlite3 gem, used only by
# test/unit/record_sqlite_test.rb's positive-path case.
#
# The real gem is not installed anywhere on this machine (checked
# both inside and outside this project's bundle while building this
# task), and the hard rule against adding a runtime dependency means
# it cannot be added just to make a test pass. This implements only
# the surface Bulldogger::Record::SqliteConverter actually calls --
# Database.new / #execute / #transaction / #close -- backed by a
# plain Array, so the positive-path test still proves the conversion
# logic itself (header line skipped, one row per event line, row
# count matches) without a real SQL engine underneath it.
module SQLite3
  class Database
    def initialize(path)
      @path = path
      @rows = []
    end

    def execute(sql, params = nil)
      return unless sql.include?("INSERT INTO events")

      seq, event, depth, line_path, line, method, payload = params
      @rows << { "seq" => seq, "event" => event, "depth" => depth, "path" => line_path,
                 "line" => line, "method" => method, "payload" => payload }
    end

    def transaction
      yield
    end

    # The real gem writes as #execute is called; this stand-in writes
    # once at #close instead. That difference is invisible to
    # SqliteConverter, which never reads the database back mid-write,
    # and to the test, which only inspects the file after conversion
    # returns.
    def close
      File.write(@path, JSON.generate(@rows))
    end
  end
end
