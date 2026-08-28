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
  # This is a thin facade over Session (the TracePoint subscription
  # and JSONL writer) and SqliteConverter (the optional, offline
  # sqlite adapter), the same shape lib/bulldogger.rb uses for
  # Capture/Run/Evidence.
  module Record
    class << self
      # Runs the block with recording on. The block runs whether or
      # not recording actually started: an app calling Record.run must
      # see its own code execute the same way with or without
      # Bulldogger, so only the trace file -- never the block -- is
      # conditional on config.enabled.
      def run
        session = start
        path = nil
        begin
          yield
        ensure
          path = session.stop
        end
        path
      end

      # config and run_dir come from the shared Bulldogger facade
      # (already public API), not a Record-owned copy: one process has
      # one run directory and one kill switch, shared by failure
      # capture, probe, and record alike.
      def start
        Session.new(config: Bulldogger.config, run_dir: Bulldogger.run_dir)
      end

      def to_sqlite(jsonl_path, db_path)
        SqliteConverter.convert(jsonl_path, db_path)
      end
    end
  end
end
