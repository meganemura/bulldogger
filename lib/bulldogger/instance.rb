# frozen_string_literal: true
# rbs_inline: enabled

module Bulldogger
  # Owns one independent capture, run, and evidence lifecycle. One module
  # singleton cannot serve as the reset subject and the outer observer. A
  # separate instance lets a test suite reset the subject while the observer
  # stays active. This class does not define file schemas or serialization.
  #
  # Each instance keeps its own :raise subscription. Two subscriptions fired
  # independently in measurements, and disabling one left the other active.
  # Each subscription cost about 0.03 microseconds per raise. A shared
  # dispatcher would add a registry and lifecycle coordination without a
  # measured need.
  class Instance
    attr_reader :config #: Config

    # @rbs @capture: Capture?
    # @rbs @run: Run?
    # @rbs @evidence: Evidence?
    # @rbs @code_state: Hash[String, String?]?

    #: (?config: Config) -> void
    def initialize(config: Config.new)
      @config = config
    end

    #: () { (Config) -> void } -> self
    def configure
      yield config
      self
    end

    #: () -> self
    def start
      return self unless config.enabled

      code_state
      capture.start
      self
    end

    #: () -> self
    def stop
      capture.stop
      self
    end

    #: () -> bool
    def running?
      capture.running?
    end

    #: (Exception exception) -> snapshot?
    def snapshot_for(exception)
      capture.snapshot_for(exception)
    end

    #: () -> Capture
    def begin_test
      capture.begin_test
    end

    #: () -> Capture
    def end_test
      capture.end_test
    end

    #: (exception: Exception?, test: test_info?) -> String?
    def record_failure(exception:, test:)
      evidence.record_failure(exception: exception, test: test)
    end

    #: () -> String?
    def run_dir
      run.dir
    end

    #: () -> void
    def finish
      run.finish
    end

    #: (*String target_strings) { () -> void } -> String?
    def probe(*target_strings, &block)
      Probe.call(target_strings, config: config, run: run, &block)
    end

    #: (*String target_strings) -> Probe::Session?
    def probe_start(*target_strings)
      Probe.start(target_strings, config: config, run: run)
    end

    #: (String path_a, String path_b) -> untyped
    def probe_compare(path_a, path_b)
      Probe.compare(path_a, path_b)
    end

    private

    #: () -> Capture
    def capture
      @capture ||= Capture.new(config: config)
    end

    #: () -> Run
    def run
      @run ||= Run.new(config: config)
    end

    #: () -> Evidence
    def evidence
      @evidence ||= Evidence.new(config: config, run: run, capture: capture, code_state: code_state)
    end

    #: () -> Hash[String, String?]
    def code_state
      @code_state ||= CodeState.capture
    end
  end
end
