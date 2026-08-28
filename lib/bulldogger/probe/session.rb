# frozen_string_literal: true

require_relative "target_resolver"
require_relative "registry"
require_relative "raise_tracker"
require_relative "method_stats"
require_relative "writer"

module Bulldogger
  module Probe
    # One probe run: resolves and reserves its targets, builds one
    # TracePoint per target (contract-verbs.md: "1 TracePoint can only
    # enable one target -- can't nest-enable a targeting TracePoint"),
    # aggregates every observed call/return into MethodStats, and
    # writes the evidence file on finish.
    class Session
      def self.start(target_strings, config:, run:)
        return nil unless config.enabled

        targets = TargetResolver.resolve!(target_strings)
        labels = targets.map(&:label)
        Registry.reserve!(labels)
        begin
          new(targets: targets, config: config, run: run).enable!
        rescue Exception # rubocop:disable Lint/RescueException
          # A target that fails mid-enable (all targets already passed
          # TargetResolver's own check, so this is the unlikely case --
          # a race with the app redefining a method, say) must not
          # leave its label stuck in Registry: that would refuse every
          # later probe of the same target for the rest of the process.
          Registry.release(labels)
          raise
        end
      end

      def self.run(target_strings, config:, run:)
        unless config.enabled
          # The switch being off must not stop the caller's own code
          # from running -- only from being observed and written. See
          # AGENTS.md: the tool must not change what the app does.
          yield if block_given?
          return nil
        end

        session = start(target_strings, config: config, run: run)
        # The written path comes from session.finish, not from
        # `begin...ensure...end`'s own value (that would be the
        # block's return value): an ensure clause's result is
        # discarded unless captured explicitly, and finish must still
        # run -- and its path still be returned -- when the block
        # raises, since a probed run that hit an exception is exactly
        # the case where the evidence is most worth having.
        result = nil
        begin
          yield
        ensure
          result = session.finish
        end
        result
      end

      def initialize(targets:, config:, run:)
        @targets = targets
        @config = config
        @run = run
        @redactor = Redactor.new(config.redact_patterns)
        @formatter = Formatter.new(config: config, redactor: @redactor)
        @stats = targets.each_with_object({}) do |target, hash|
          hash[target.label] = MethodStats.new(target: target, formatter: @formatter, redactor: @redactor,
                                                 max_samples: config.max_samples)
        end
        @trace_points = []
        @started_at = Time.now.utc
        @finished = false
        @finish_mutex = Mutex.new
      end

      def enable!
        RaiseTracker.instance.acquire
        @targets.each do |target|
          tp = build_trace_point(@stats[target.label])
          tp.enable(target: target.unbound_method)
          @trace_points << tp
        end
        self
      rescue Exception # rubocop:disable Lint/RescueException
        @trace_points.each(&:disable)
        RaiseTracker.instance.release
        raise
      end

      def finish
        @finish_mutex.synchronize do
          return @result_path if @finished

          @finished = true
          @trace_points.each(&:disable)
          RaiseTracker.instance.release
          Registry.release(@targets.map(&:label))
          @result_path = Writer.write(run: @run, config: @config, targets: @targets, stats: @stats,
                                       started_at: @started_at)
        end
      end

      private

      # A one-line delegation, matching every other hook in this
      # codebase (Capture, RaiseTracker, Record::Session): the block
      # given to TracePoint.new does no work itself, it only calls a
      # named method. That method is what a direct unit test calls
      # too, with a double standing in for tp, so this hook's own
      # routing logic is covered by an ordinary test and not just by
      # the hook actually firing (which stdlib Coverage cannot see
      # inside).
      def build_trace_point(stats)
        TracePoint.new(:call, :return) { |tp| dispatch(tp, stats) }
      end

      # Delegating the block body to this named method adds one real
      # call frame between the app's own call site and where
      # caller_locations runs -- measured directly (the block calling
      # a method that calls caller_locations puts one extra frame
      # under caller_locations, versus caller_locations running
      # straight inside the block) -- so the offset here is 3, not the
      # 2 a bare inline block needed before this method existed.
      # probe_caller_offset_test.rb pins this number against this
      # exact shape.
      #
      # Only the first frame is ever kept (`.first` was called on a
      # 3-frame array before this hook existed), so only 1 frame is
      # requested here. Measured at ~300ns/call, caller_locations is
      # the single most expensive thing this hook does -- 4-5x the
      # cost of TracePoint's own dispatch -- and building frames this
      # code never reads was pure waste.
      def dispatch(tp, stats)
        case tp.event
        when :call
          RaiseTracker.instance.push_checkpoint
          caller_loc = caller_locations(3, 1)&.first
          stats.record_call(tp, caller_loc)
        when :return
          # Popped before record_return, not after: even if
          # record_return itself raises (caught below), the
          # checkpoint stack for this fiber is already balanced, so a
          # later call on the same fiber is never thrown off by an
          # earlier one's formatting failure.
          raised = RaiseTracker.instance.pop_and_raised_exit?
          stats.record_return(tp, raised: raised)
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        # The hook must never let an exception escape into the probed
        # method's own call/return path -- doing so would replace the
        # app's real control flow with one from inside this library.
        # Same rule as Capture's :raise hook.
        warn("bulldogger: probe hook failed: #{e.class}: #{e.message}") if ENV["BULLDOGGER_DEBUG"] == "1"
      end
    end
  end
end
