# frozen_string_literal: true

require "json"

module Bulldogger
  module Record
    # Converts an existing trace-NNN.jsonl into a SQLite database, one
    # row per event line.
    #
    # sqlite3 is required here, and only inside #convert (soft
    # require) -- never at the top of this file. The design principle
    # is "CLI and any servers are thin adapters over the files": a
    # live SQLite writer running alongside the JSONL writer would make
    # SQLite a second product instead of an adapter, and requiring the
    # gem unconditionally would add a runtime dependency the core does
    # not carry. When sqlite3 is not installed, this returns nil
    # rather than raising, so a caller that never asked for SQL access
    # is never broken by its absence.
    module SqliteConverter
      class << self
        def convert(jsonl_path, db_path)
          require "sqlite3"
        rescue LoadError => e
          # Unconditional, not gated by BULLDOGGER_DEBUG: the contract
          # requires an explicit signal, not a silent nil, when sqlite3
          # is unavailable ("使えないことを明示的に伝えて nil を返す").
          # The debug gate elsewhere in this codebase exists for the
          # :call/:return/:raise hooks, which fire on every traced
          # event and must stay silent by default; to_sqlite is a
          # single explicit call a caller made on purpose, never a hot
          # path, so warning every time costs nothing worth hiding.
          warn("bulldogger: sqlite3 not available (#{e.class}: #{e.message}); to_sqlite returning nil")
          nil
        else
          write_database(jsonl_path, db_path)
          db_path
        end

        private

        def write_database(jsonl_path, db_path)
          File.delete(db_path) if File.exist?(db_path)
          db = SQLite3::Database.new(db_path)
          create_table(db)
          insert_events(db, jsonl_path)
        ensure
          db&.close
        end

        def create_table(db)
          db.execute(<<~SQL)
            CREATE TABLE events (
              seq INTEGER,
              event TEXT,
              depth INTEGER,
              path TEXT,
              line INTEGER,
              method TEXT,
              payload TEXT
            )
          SQL
        end

        # One row per JSONL line after the header. payload keeps the
        # full original JSON object (args/return/exception vary by
        # event kind and do not fit fixed columns without inventing a
        # shape the JSONL schema itself does not have); the other
        # columns exist so a caller can filter and order with plain
        # SQL instead of parsing payload on every row.
        def insert_events(db, jsonl_path)
          db.transaction do
            File.foreach(jsonl_path).with_index do |line, index|
              next if index.zero? # header line, not an event

              row = JSON.parse(line)
              db.execute(
                "INSERT INTO events (seq, event, depth, path, line, method, payload) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [row["seq"], row["event"], row["depth"], row["path"], row["line"], row["method"], line.chomp]
              )
            end
          end
        end
      end
    end
  end
end
