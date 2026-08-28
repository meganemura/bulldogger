# frozen_string_literal: true

require "json"
require "fileutils"

module Bulldogger
  module Record
    # Appends one JSON object per line to trace-NNN.jsonl, plus a
    # header line written once at construction.
    #
    # The NNN is picked by scanning the run directory for existing
    # trace-*.jsonl files, not an in-memory counter: Run (owned
    # elsewhere) already hands out its own NNN-slug.json sequence for
    # evidence files, and a Record session has no access to that
    # counter -- nor should it share one, since "trace-NNN" and
    # "NNN-slug" are different filename shapes with no shared meaning
    # to a reader comparing NNN values across them.
    class Writer
      FILENAME_PATTERN = /\Atrace-(\d+)\.jsonl\z/

      @reserve_mutex = Mutex.new

      attr_reader :path

      def initialize(run_dir:, header:)
        @path = self.class.reserve_path(run_dir)
        @io = File.open(@path, "w")
        write_line(header)
      end

      def write_event(event)
        write_line(event)
      end

      def close
        @io.close
        @path
      end

      class << self
        # Reserves the next trace-NNN.jsonl name under a process-wide
        # lock. Two sessions starting back to back (or on two threads)
        # must never both see the same "no trace-*.jsonl yet" listing
        # and pick the same NNN, so the file is created (empty) while
        # still holding the lock -- closing the window where a second
        # scan could run before the first session's file exists on
        # disk. The lock only spans this rare, brief start-up step,
        # never a per-event write.
        def reserve_path(run_dir)
          @reserve_mutex.synchronize do
            existing = Dir.children(run_dir).filter_map { |name| name[FILENAME_PATTERN, 1]&.to_i }
            next_n = (existing.max || 0) + 1
            path = File.join(run_dir, format("trace-%03d.jsonl", next_n))
            FileUtils.touch(path)
            path
          end
        end
      end

      private

      def write_line(hash)
        @io.write("#{JSON.generate(hash)}\n")
      end
    end
  end
end
