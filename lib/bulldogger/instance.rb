# frozen_string_literal: true

module Bulldogger
  # Owns one independent capture, run, and evidence lifecycle.
  # File schemas and serialization behavior remain in their existing classes.
  class Instance
    attr_reader :config

    def initialize(config: Config.new)
      @config = config
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

    def probe(*target_strings, &block)
      Probe.call(target_strings, config: config, run: run, &block)
    end

    def probe_start(*target_strings)
      Probe.start(target_strings, config: config, run: run)
    end

    def probe_compare(path_a, path_b)
      Probe.compare(path_a, path_b)
    end

    def record(&block)
      Record.run(instance: self, &block)
    end

    def record_start
      Record.start(instance: self)
    end

    def trace_to_sqlite(jsonl_path, db_path)
      Record.to_sqlite(jsonl_path, db_path)
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
