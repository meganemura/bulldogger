# frozen_string_literal: true

require_relative "bulldogger/version"
require_relative "bulldogger/config"
require_relative "bulldogger/capture"
require_relative "bulldogger/run"
require_relative "bulldogger/evidence"

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
  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield config
      self
    end

    def start
      return self unless config.enabled

      capture.start
      self
    end

    def stop
      capture.stop
      self
    end

    def running?
      capture.running?
    end

    def snapshot_for(exception)
      capture.snapshot_for(exception)
    end

    def record_failure(exception:, test:)
      evidence.record_failure(exception: exception, test: test)
    end

    def run_dir
      run.dir
    end

    def finish
      run.finish
    end

    private

    def capture
      @capture ||= Capture.new(config: config)
    end

    def run
      @run ||= Run.new(config: config)
    end

    def evidence
      @evidence ||= Evidence.new(config: config, run: run, capture: capture)
    end
  end
end
