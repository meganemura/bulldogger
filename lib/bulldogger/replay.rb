# frozen_string_literal: true

require "open3"
require "rbconfig"
require "timeout"

module Bulldogger
  # Records one failed test again because a failure snapshot can miss the cause.
  # The application method has returned when an assertion raises. In one
  # third-party gem, its snapshot could not reveal a one-character fault.
  # Additional stack frames were rejected because they cannot contain that call.
  # Replay observes a new execution and records the application call.
  # This class does not change the parent test result or record green tests.
  class Replay
    def initialize(config:)
      @config = config
      @count = 0
      @mutex = Mutex.new
    end

    def call(test:, run_dir:, frames: [])
      return unless eligible?(test)
      if @config.replay_on_failure != :always && application_frame_available?(test, frames: frames)
        return { skipped_reason: "application_frame_available" }
      end
      return unless reserve

      before = traces(run_dir)
      _stdout, _stderr, status = Timeout.timeout(@config.replay_timeout) do
        Open3.capture3(child_env(run_dir), *command(test))
      end
      path = (traces(run_dir) - before).last
      { path: path, reproduced: !status.success? }
    # Replay is diagnostic work. A timeout, crash, or setup error must not
    # change the parent exit code or add a failure to the parent suite.
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn("bulldogger: replay failed: #{e.class}: #{e.message}") if ENV["BULLDOGGER_DEBUG"] == "1"
      nil
    end

    # The replay uses a child because an in-process run can pollute global state
    # and change the parent result. Parent recording was rejected because it
    # makes green runs about sixty times slower. The child confines this cost.
    #
    # This method starts recording before the test framework starts. A later
    # start can miss boot calls that the test needs. The method also gives the
    # coverage suite a callable seam. Ruby loads command-line requirements
    # before the coverage setup in RUBYOPT, so coverage cannot see the call site.
    def self.boot_replay_child!(run_dir: ENV.fetch("BULLDOGGER_REPLAY_RUN_DIR"))
      require_relative "../bulldogger"
      replay_instance = Struct.new(:config, :run_dir).new(Bulldogger::Config.new, run_dir)
      session = Bulldogger::Record.start(instance: replay_instance)
      at_exit { session.stop }
      session
    end

    private

    def application_frame_available?(test, frames:)
      test_path = File.expand_path(test[:file])
      frames.any? do |frame|
        raw_path = frame["path"].to_s
        next false if raw_path.empty?

        path = File.expand_path(raw_path)
        path != test_path && !library_path?(path)
      end
    end

    def library_path?(path)
      library_paths.any? { |prefix| path.start_with?(prefix) }
    end

    def library_paths
      # A vendored bundle can sit inside the project. Gem.path still names it,
      # so project-directory classification alone would replay this case.
      # Checking only frame zero was rejected because a gem can raise while an
      # application caller remains on the stack with the values a reader needs.
      Gem.path + RbConfig::CONFIG.values_at("rubylibdir", "sitelibdir").compact
    end

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

    # A new Ruby process loses paths that the parent boot added. Without those
    # paths, a test can fail to load its helper. Its trace then has boot events
    # but no application calls. This failure occurred in a third-party gem.
    #
    # The filter drops Ruby library paths and installed gem paths. The child
    # rebuilds them from Ruby, RubyGems, Bundler, and the inherited environment.
    # Forwarding them would add hundreds of duplicate command arguments. The
    # child receives paths outside the Ruby and gem directory prefixes.
    #
    # Separate -I arguments preserve spaces in paths. A RUBYOPT string would
    # require parsing and shell quoting, which can change a valid path.
    def forwarded_load_path_flags
      builtin_dirs = RbConfig::CONFIG.values_at("rubylibdir", "sitedir", "vendordir").compact
      installed_gem_dirs = Gem.path
      excluded = builtin_dirs + installed_gem_dirs

      # Some apps add Pathname values. String#start_with? would reject them and
      # prevent replay, so conversion keeps an app load path usable.
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
