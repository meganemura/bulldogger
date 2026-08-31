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
    def self.minitest_plugin_init(_options)
      return if @wired

      @wired = true
      # The child records full execution. A second failure observer could start
      # nested replay and could change the isolated test result.
      return if ENV["BULLDOGGER_REPLAY_CHILD"] == "1"

      instance.start
      ::Minitest.reporter << Reporter.new
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
      def prerecord(_klass, _name)
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

      # First choice: tag the failure exception's own #message, so the
      # one line sits inside the same text Minitest's SummaryReporter
      # already prints for this failure. A raised exception can be
      # frozen (a re-raised literal, an app that freezes its errors),
      # and #define_singleton_method on a frozen object raises --
      # fall back to printing the line ourselves so a frozen exception
      # never means a silently missing evidence line.
      def annotate!(failure, path)
        original = failure.message
        lines = FailureOutput.lines(path, replay_enabled: Minitest.instance.config.replay_on_failure)
        suffix = "\n#{lines.join("\n")}"
        failure.define_singleton_method(:message) { "#{original}#{suffix}" }
      rescue FrozenError
        $stdout.puts lines
      end
    end
  end
end

::Minitest.register_plugin(Bulldogger::Minitest)
