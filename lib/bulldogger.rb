# frozen_string_literal: true

require_relative "bulldogger/version"
require_relative "bulldogger/config"
require_relative "bulldogger/capture"
require_relative "bulldogger/run"
require_relative "bulldogger/evidence"
require_relative "bulldogger/probe"
require_relative "bulldogger/instance"

# Ruby execution evidence for coding agents, as files: a failing test
# writes a structured snapshot of its own failure, so an agent can read
# runtime values instead of guessing them from source.
#
# This module is a thin facade. It wires Capture (the :raise
# subscription and its ring of pending snapshots), Run (the on-disk
# run directory), and Evidence (assembling and writing one failure's
# JSON) together, and holds the process-global state a test run needs
# -- one TracePoint, one run directory. No capture, formatting, or
# redaction logic lives here; see capture.rb, formatter.rb, and
# redactor.rb.
module Bulldogger
  # Autoloaded rather than required at the top of this file, because
  # record.rb requires this file back: Record.start reads
  # Bulldogger.config and Bulldogger.run_dir, so `require
  # "bulldogger/record"` on its own has to work. Requiring in both
  # directions makes a cycle, and Ruby warns that one file will see
  # the other half-defined. Deferring until Bulldogger::Record is first
  # named breaks it -- by then this file has finished loading, so
  # record.rb's require of it is a no-op.
  autoload :Record, File.expand_path("bulldogger/record", __dir__)

  class << self
    def default
      @default ||= Instance.new
    end

    def config
      default.config
    end

    def configure
      default.configure { |config| yield config }
      self
    end

    def start
      default.start
      self
    end

    def stop
      default.stop
      self
    end

    def running?
      default.running?
    end

    def snapshot_for(exception)
      default.snapshot_for(exception)
    end

    def record_failure(exception:, test:)
      default.record_failure(exception: exception, test: test)
    end

    def run_dir
      default.run_dir
    end

    def finish
      default.finish
    end

    # Watches target_strings (each "Klass#method" or "Klass.method")
    # for the life of the block and writes one evidence file
    # summarizing every call's argument/return shape. See
    # lib/bulldogger/probe.rb. Returns the written path, or nil if the
    # switch is off -- the block still runs either way, only the
    # observing and writing are skipped.
    def probe(*target_strings, &block)
      default.probe(*target_strings, &block)
    end

    # Explicit-session counterpart to #probe: call session.finish to
    # stop watching and write the evidence file. Returns nil, not a
    # session, when the switch is off -- callers must guard the same
    # way every other disabled-switch return value here is guarded.
    def probe_start(*target_strings)
      default.probe_start(*target_strings)
    end

    def probe_compare(path_a, path_b)
      default.probe_compare(path_a, path_b)
    end

    # Traces every call, return, and raise in the block to a JSONL
    # file. See lib/bulldogger/record.rb. Returns the written path, or
    # nil if the switch is off. This is the expensive verb, which is
    # why it is a verb: it costs roughly 4500ns per traced call, on
    # every call rather than on a named few.
    def record(&block)
      default.record(&block)
    end

    # Explicit-session counterpart to #record: call session.stop to
    # finish the trace and get its path.
    def record_start
      default.record_start
    end

    # Converts a written trace into SQLite for indexed querying.
    # Returns nil when the sqlite3 gem is absent, which is the normal
    # case -- JSONL is the canonical format and this is an adapter over
    # it, so bulldogger never depends on sqlite3 at runtime.
    def trace_to_sqlite(jsonl_path, db_path)
      default.trace_to_sqlite(jsonl_path, db_path)
    end

    private

    def capture
      default.send(:capture)
    end
  end
end
