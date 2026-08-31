# frozen_string_literal: true

require "minitest"
require_relative "../../bulldogger"
require_relative "../failure_output"

module Bulldogger
  # Connects Minitest failures to evidence and replay paths.
  # It does not change test isolation, exception handling, or test results.
  module Minitest
    class << self
      attr_writer :instance

      # Dogfood assigns an outer observer that the suite's default reset cannot
      # reach. Normal users keep the default instance without extra setup.
      def instance
        @instance || Bulldogger.default
      end
    end

    # Minitest's own extension point: Minitest.register_plugin with a
    # Module makes Minitest call #minitest_plugin_init once, during
    # Minitest.run, at the one moment Minitest.reporter is set (the
    # accessor is nil outside that window). That is why Bulldogger.start
    # and the reporter wiring happen here and not at require time --
    # nothing has run yet, so nothing needs the TracePoint before this.
    def self.minitest_plugin_init(options)
      return if @wired

      @wired = true
      # The child records full execution. A second failure observer could start
      # nested replay and could change the isolated test result.
      return if ENV["BULLDOGGER_REPLAY_CHILD"] == "1"

      instance.start
      ::Minitest.reporter << Reporter.new(options[:io] || $stdout)
      ::Minitest.after_run do
        instance.finish
        instance.stop
      end
    end

    # Turns one finished test into a Bulldogger evidence file.
    # Registered into Minitest's CompositeReporter, so #record runs
    # once per test method, pass or fail. Minitest.run_one_method
    # always returns a Minitest::Result, never the Test instance
    # itself, so the test's id/file/line come from Result's own
    # klass/name/source_location rather than from re-deriving them.
    class Reporter < ::Minitest::AbstractReporter
      attr_reader :io

      # AbstractReporter#initialize takes no arguments; this reporter
      # keeps its own io so #annotate! can print to it directly instead
      # of depending on the failure's own #message reaching the runner's
      # output. A Rails-wrapped Minitest 6 run proved that dependency
      # false: Rails' SuppressedSummaryReporter skips the deferred
      # failure printout, and its own inline reporter runs before this
      # one, so a rewritten #message never surfaces anywhere.
      def initialize(io = $stdout)
        super()
        @io = io
      end

      def prerecord(_klass, _name)
        Bulldogger::FramesCollector.begin_test if defined?(Bulldogger::FramesCollector)
        Bulldogger::FltCollector.begin_test if defined?(Bulldogger::FltCollector)
        Bulldogger::ExecCollector.begin_test if defined?(Bulldogger::ExecCollector)
        Minitest.instance.begin_test
      end

      def record(result)
        return if ENV["BULLDOGGER_REPLAY_CHILD"] == "1"

        failure = result.failure
        return if failure.nil? || result.skipped?

        exception = exception_for(failure)
        path = Minitest.instance.record_failure(exception: exception, test: test_for(result))
        annotate!(failure, path) if path
      ensure
        Minitest.instance.end_test unless ENV["BULLDOGGER_REPLAY_CHILD"] == "1"
        Bulldogger::FramesCollector.end_test if defined?(Bulldogger::FramesCollector)
        Bulldogger::FltCollector.end_test if defined?(Bulldogger::FltCollector)
        Bulldogger::ExecCollector.end_test if defined?(Bulldogger::ExecCollector)
      end

      private

      # UnexpectedError wraps whatever the app actually raised;
      # #error unwraps it, and is defined to return self on a plain
      # Assertion, so this one line also covers assertion failures
      # without a separate branch. The wrapper itself is only ever
      # `.new`'d, never `raise`'d, so :raise only fires for the inner
      # exception -- snapshot_for is still tried on both, in that
      # order, so nothing breaks if a future Minitest version starts
      # re-raising the wrapper instead.
      def exception_for(failure)
        inner = failure.respond_to?(:error) ? failure.error : failure
        return inner if Minitest.instance.snapshot_for(inner)
        return failure if Minitest.instance.snapshot_for(failure)

        inner
      end

      def test_for(result)
        file, line = result.source_location
        {
          framework: "minitest",
          id: "#{result.class_name}##{result.name}",
          file: file,
          line: line,
          seed: ::Minitest.seed
        }
      end

      # Prints straight to this reporter's own io rather than tagging
      # the failure exception's own #message: whether a rewritten
      # #message reaches the runner's output depends on which other
      # reporters are installed and in what order, and a host that
      # wraps Minitest (Rails' SuppressedSummaryReporter, run before
      # this reporter under Minitest 6) can drop it silently. Printing
      # here needs nothing from the failure object, so a frozen
      # exception (a re-raised literal, an app that freezes its errors)
      # never means a missing evidence line either.
      def annotate!(_failure, path)
        lines = FailureOutput.lines(path, replay_enabled: Minitest.instance.config.replay_on_failure)
        synchronize { io.puts lines }
      end
    end
  end
end

::Minitest.register_plugin(Bulldogger::Minitest)
