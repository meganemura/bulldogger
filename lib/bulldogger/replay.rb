# frozen_string_literal: true

require "open3"
require "rbconfig"
require "timeout"

module Bulldogger
  # Replays one failed test in an isolated process with full recording.
  # Replay failures stay diagnostic and cannot change the parent suite result.
  class Replay
    def initialize(config:)
      @config = config
      @count = 0
      @mutex = Mutex.new
    end

    def call(test:, run_dir:)
      return unless eligible?(test)
      return unless reserve

      before = traces(run_dir)
      _stdout, _stderr, status = Timeout.timeout(@config.replay_timeout) do
        Open3.capture3(child_env(run_dir), *command(test))
      end
      path = (traces(run_dir) - before).last
      { path: path, reproduced: !status.success? }
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn("bulldogger: replay failed: #{e.class}: #{e.message}") if ENV["BULLDOGGER_DEBUG"] == "1"
      nil
    end

    # Boots this process as the replay child: starts a Record session
    # writing into the same run directory the parent's evidence lives
    # in. A class method, not inline code at the bottom of this file,
    # so a unit test can call it directly -- necessary because the
    # call site below is unreachable to `rake coverage`'s own
    # instrumentation. Ruby processes a command line's own -r flags
    # before RUBYOPT's (confirmed empirically: a marker file required
    # via -r on the command line logs before one required via
    # RUBYOPT), and #command always puts "-rbulldogger/replay" on the
    # command line by design -- the child must start recording before
    # the test framework itself boots, not after. So in a
    # coverage-instrumented run this file is fully loaded, and the
    # call site below already evaluated, before Coverage.start (loaded
    # via RUBYOPT) ever runs. The method body has no such problem:
    # called from a normal `require`d context such as a unit test, it
    # runs after Coverage.start like anything else. The same
    # limitation, and the same fix, already applies to
    # lib/bulldogger/version.rb -- see test/test_helper.rb.
    def self.boot_replay_child!(run_dir: ENV.fetch("BULLDOGGER_REPLAY_RUN_DIR"))
      require_relative "../bulldogger"
      replay_instance = Struct.new(:config, :run_dir).new(Bulldogger::Config.new, run_dir)
      session = Bulldogger::Record.start(instance: replay_instance)
      at_exit { session.stop }
      session
    end

    private

    def eligible?(test)
      @config.enabled && @config.replay_on_failure && ENV["BULLDOGGER_REPLAY_CHILD"] != "1" &&
        test && test[:file] && %w[minitest rspec].include?(test[:framework])
    end

    def reserve
      @mutex.synchronize do
        return false if @count >= @config.max_replays

        @count += 1
        true
      end
    end

    def command(test)
      lib = File.expand_path("..", __dir__)
      load_path = ["-I#{lib}", *forwarded_load_path_flags]
      if test[:framework] == "minitest"
        [RbConfig.ruby, *load_path, "-rbulldogger/replay", test[:file], "-n", test[:id].to_s.split("#", 2).last]
      else
        rspec = Gem.bin_path("rspec-core", "rspec")
        [RbConfig.ruby, *load_path, "-rbulldogger/replay", rspec, "#{test[:file]}:#{test[:line]}"]
      end
    end

    # The child is a fresh `ruby` invocation, not a fork: it starts
    # with only Ruby's own default $LOAD_PATH, none of what the
    # parent's boot script added on top. Measured against a real gem
    # (crmne/archspec): its test files `require "test_helper"` relying
    # on Rake::TestTask's own `-Itest`, and without forwarding that
    # directory the child died on load before a single application
    # frame reached the trace.
    #
    # Forwarding is filtered, not the whole $LOAD_PATH verbatim:
    # Ruby's own stdlib/site/vendor directories and every installed
    # gem's lib/ are already on the child's $LOAD_PATH from its own
    # boot (RbConfig's paths are compiled in; Bundler/RubyGems
    # re-derive gem paths from the inherited environment -- GEM_HOME,
    # BUNDLE_GEMFILE -- the same way the parent did). Re-adding
    # hundreds of those as -I flags would be pure noise on the command
    # line. What is NOT already there, and DOES need forwarding, is
    # whatever the app's own boot script added on top of that --
    # test/, a custom lib/ variant, and similar.
    #
    # -I flags, not RUBYOPT, carry the result: each path is its own
    # array element, so a path containing a space needs no
    # shell-quoting logic of its own the way splitting a single
    # RUBYOPT string on whitespace would.
    def forwarded_load_path_flags
      builtin_dirs = RbConfig::CONFIG.values_at("rubylibdir", "sitedir", "vendordir").compact
      installed_gem_dirs = Gem.path
      excluded = builtin_dirs + installed_gem_dirs

      # to_s guards against a $LOAD_PATH entry that is a Pathname
      # rather than a String (some apps push those) -- start_with?
      # would raise on one, and #call's own `rescue Exception` would
      # then swallow the whole replay silently, which is the exact
      # failure shape this feature exists to avoid.
      $LOAD_PATH.map(&:to_s)
                .reject { |path| excluded.any? { |dir| path.start_with?(dir) } }
                .uniq
                .map { |path| "-I#{path}" }
    end

    def child_env(run_dir)
      {
        "BULLDOGGER_REPLAY_CHILD" => "1",
        "BULLDOGGER_REPLAY" => "0",
        "BULLDOGGER_REPLAY_RUN_DIR" => run_dir
      }
    end

    def traces(run_dir)
      Dir.glob(File.join(run_dir, "trace-*.jsonl")).sort
    end
  end
end

Bulldogger::Replay.boot_replay_child! if ENV["BULLDOGGER_REPLAY_CHILD"] == "1"
