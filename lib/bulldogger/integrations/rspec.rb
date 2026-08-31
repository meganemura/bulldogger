# frozen_string_literal: true

require "rspec/core"
require_relative "../../bulldogger"
require_relative "../failure_output"

module Bulldogger
  # Connects RSpec failures to evidence and replay paths.
  # It does not control test execution, formatter behavior, or test results.
  module RSpec
    class << self
      attr_writer :instance

      # Dogfood can assign an isolated observer. The default preserves the
      # normal integration API for applications that need one lifecycle.
      def instance
        @instance || Bulldogger.default
      end
    end

    # RSpec has already scored the example's description and its
    # file/line into metadata by the time after(:each) runs; test_for
    # reads those off the Example instead of re-deriving them.
    def self.test_for(example)
      {
        framework: "rspec",
        id: example.full_description,
        file: example.metadata[:file_path],
        line: example.metadata[:line_number],
        seed: ::RSpec.configuration.seed
      }
    end

    # Tags the exception's own #message, so the evidence line sits
    # inside the same text RSpec's own formatter prints for this
    # failure. This after(:each) hook runs synchronously inside
    # Example#run, before RSpec's reporter notifies any formatter, so
    # the rewrite is guaranteed to land before anything reads the
    # message -- unlike Minitest's CompositeReporter, RSpec has no
    # second observer that could print the failure first. A frozen
    # exception can't take a singleton method; fall back to printing
    # the line directly so a frozen exception never means a silently
    # missing evidence line.
    def self.annotate!(exception, path)
      original = exception.message
      lines = FailureOutput.lines(path, replay_enabled: instance.config.replay_on_failure)
      suffix = "\n#{lines.join("\n")}"
      exception.define_singleton_method(:message) { "#{original}#{suffix}" }
    rescue FrozenError
      $stdout.puts lines
    end
  end
end

::RSpec.configure do |config|
  # The child records full execution. Failure hooks could start nested replay
  # and could change the isolated test result, so the child skips these hooks.
  config.before(:suite) { Bulldogger::RSpec.instance.start unless ENV["BULLDOGGER_REPLAY_CHILD"] == "1" }
  config.before(:each) do
    Bulldogger::FramesCollector.begin_test if defined?(Bulldogger::FramesCollector)
    Bulldogger::FltCollector.begin_test if defined?(Bulldogger::FltCollector)
    Bulldogger::ExecCollector.begin_test if defined?(Bulldogger::ExecCollector)
    Bulldogger::RSpec.instance.begin_test unless ENV["BULLDOGGER_REPLAY_CHILD"] == "1"
  end

  # after(:each), not a formatter hook: example.exception is already
  # set by the time this runs (Example#run assigns it before
  # run_after_example fires the after(:each) hooks), and evidence
  # must be written -- and the exception's #message annotated -- before
  # RSpec's own formatters render the failure, or the added line would
  # never reach the user's terminal.
  config.after(:each) do |example|
    next if ENV["BULLDOGGER_REPLAY_CHILD"] == "1"

    exception = example.exception
    next unless exception

    path = Bulldogger::RSpec.instance.record_failure(exception: exception, test: Bulldogger::RSpec.test_for(example))
    Bulldogger::RSpec.annotate!(exception, path) if path
  ensure
    Bulldogger::RSpec.instance.end_test unless ENV["BULLDOGGER_REPLAY_CHILD"] == "1"
    Bulldogger::FramesCollector.end_test if defined?(Bulldogger::FramesCollector)
    Bulldogger::FltCollector.end_test if defined?(Bulldogger::FltCollector)
    Bulldogger::ExecCollector.end_test if defined?(Bulldogger::ExecCollector)
  end

  config.after(:suite) do
    next if ENV["BULLDOGGER_REPLAY_CHILD"] == "1"

    Bulldogger::RSpec.instance.finish
    Bulldogger::RSpec.instance.stop
  end
end
