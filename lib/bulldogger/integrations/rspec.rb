# frozen_string_literal: true

require "rspec/core"
require "json"
require_relative "../../bulldogger"

module Bulldogger
  # Connects RSpec lifecycle events to one selected Bulldogger instance.
  # It does not control RSpec execution or formatter behavior.
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
        line: example.metadata[:line_number]
      }
    end

    # Mirrors the minitest integration's annotate!: tag the exception's
    # own #message first, so the evidence line sits inside the same
    # text RSpec's own formatter already prints for this failure. A
    # frozen exception can't take a singleton method; fall back to
    # printing the line directly so a frozen exception never means a
    # silently missing evidence line.
    def self.annotate!(exception, path)
      original = exception.message
      replay_path = JSON.parse(File.read(path))["replay"]
      suffix = "\nbulldogger evidence: #{path}"
      suffix += "\nbulldogger replay: #{replay_path}" if replay_path
      exception.define_singleton_method(:message) { "#{original}#{suffix}" }
    rescue FrozenError
      $stdout.puts "bulldogger evidence: #{path}"
      $stdout.puts "bulldogger replay: #{replay_path}" if replay_path
    rescue JSON::ParserError, SystemCallError
      exception.define_singleton_method(:message) { "#{original}\nbulldogger evidence: #{path}" }
    end
  end
end

::RSpec.configure do |config|
  config.before(:suite) { Bulldogger::RSpec.instance.start unless ENV["BULLDOGGER_REPLAY_CHILD"] == "1" }

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
  end

  config.after(:suite) do
    next if ENV["BULLDOGGER_REPLAY_CHILD"] == "1"

    Bulldogger::RSpec.instance.finish
    Bulldogger::RSpec.instance.stop
  end
end
