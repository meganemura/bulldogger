# frozen_string_literal: true

require_relative "../bulldogger"
require_relative "record/session"
require_relative "record/sqlite_converter"

module Bulldogger
  # Full, unfiltered method-call recording, as an explicit verb rather
  # than an ambient default. Where Capture answers "what failed" from
  # a single :raise, Record answers "what happened" across a block:
  # every :call, :return, and :raise event in the process while the
  # block runs, one JSON object per line. This is the heavy path
  # AGENTS.md reserves for an explicit request -- see
  # tasks/record.rake for the measured cost of turning it on.
  #
  # This module coordinates Session and the optional SQLite adapter. It does
  # not own the selected instance or its failure-capture lifecycle.
  module Record
    class << self
      # Runs the block with recording on. The block runs whether or
      # not recording actually started: an app calling Record.run must
      # see its own code execute the same way with or without
      # Bulldogger, so only the trace file -- never the block -- is
      # conditional on config.enabled.
      def run(instance: Bulldogger.default)
        session = start(instance: instance)
        path = nil
        begin
          yield
        ensure
          path = session.stop
        end
        path
      end

      # Record formerly read Bulldogger.config and Bulldogger.run_dir directly.
      # The instance parameter selects the config and run state, as Probe does.
      def start(instance: Bulldogger.default)
        Session.new(config: instance.config, run_dir: instance.run_dir)
      end

      def to_sqlite(jsonl_path, db_path)
        SqliteConverter.convert(jsonl_path, db_path)
      end
    end
  end
end
