# frozen_string_literal: true
# rbs_inline: enabled

require_relative "bulldogger/version"
require_relative "bulldogger/config"
require_relative "bulldogger/code_state"
require_relative "bulldogger/rerun_command"
require_relative "bulldogger/capture"
require_relative "bulldogger/run"
require_relative "bulldogger/evidence"
require_relative "bulldogger/probe"
require_relative "bulldogger/instance"

# Ruby execution evidence for coding agents, as files: a failing test
# writes a structured snapshot of its own failure, so an agent can read
# runtime values instead of guessing them from source.
#
# This module is a thin facade over a default Instance. Separate instances let
# a tool observe a suite that resets the default instance during test setup.
# This module does not own capture, formatting, or redaction logic.
module Bulldogger
  # @rbs!
  #   # A snapshot the :raise hook built, already rendered to strings.
  #   type snapshot = Hash[String, untyped]
  #
  #   # What a test framework integration knows about one test: framework, id, file, line, seed.
  #   type test_info = Hash[Symbol, untyped]
  #
  #   # A document written to or read from JSON, with string keys.
  #   type json = Hash[String, untyped]

  # @rbs self.@default: Instance?

  class << self
    # Test setup can replace this default for isolation. An explicitly created
    # Instance keeps an outer observer alive when the default is replaced.
    #: () -> Instance
    def default
      @default ||= Instance.new
    end

    #: () -> Config
    def config
      default.config
    end

    #: () { (Config) -> void } -> singleton(Bulldogger)
    def configure
      default.configure { |config| yield config }
      self
    end

    #: () -> singleton(Bulldogger)
    def start
      default.start
      self
    end

    #: () -> singleton(Bulldogger)
    def stop
      default.stop
      self
    end

    #: () -> bool
    def running?
      default.running?
    end

    #: (Exception exception) -> snapshot?
    def snapshot_for(exception)
      default.snapshot_for(exception)
    end

    #: () -> Capture
    def begin_test
      default.begin_test
    end

    #: () -> Capture
    def end_test
      default.end_test
    end

    #: (exception: Exception?, test: test_info?) -> String?
    def record_failure(exception:, test:)
      default.record_failure(exception: exception, test: test)
    end

    #: () -> String?
    def run_dir
      default.run_dir
    end

    #: () -> void
    def finish
      default.finish
    end

    # Watches target_strings (each "Klass#method" or "Klass.method")
    # for the life of the block and writes one evidence file
    # summarizing every call's argument/return shape. See
    # lib/bulldogger/probe.rb. Returns the written path, or nil if the
    # switch is off -- the block still runs either way, only the
    # observing and writing are skipped.
    #: (*String target_strings) { () -> void } -> String?
    def probe(*target_strings, &block)
      default.probe(*target_strings, &block)
    end

    # Explicit-session counterpart to #probe: call session.finish to
    # stop watching and write the evidence file. Returns nil, not a
    # session, when the switch is off -- callers must guard the same
    # way every other disabled-switch return value here is guarded.
    #: (*String target_strings) -> Probe::Session?
    def probe_start(*target_strings)
      default.probe_start(*target_strings)
    end

    #: (String path_a, String path_b) -> untyped
    def probe_compare(path_a, path_b)
      default.probe_compare(path_a, path_b)
    end

    private

    #: () -> Capture
    def capture
      default.send(:capture)
    end
  end
end
