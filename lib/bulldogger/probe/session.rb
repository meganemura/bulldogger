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

      # caller_locations(2, 1) is called directly inside this block --
      # not delegated to a further method -- because the offset that
      # lands on the app's own call site was measured against exactly
      # this shape (a bare block given to TracePoint.new). The block's
      # *definition* site (this builder method) does not add a call
      # frame at *invocation* time, only where it is actually invoked
      # from does, so building it here rather than inline in enable!
      # does not change the offset.
      #
      # Only the first frame is ever kept (`.first` was called on a
      # 3-frame array before), so only 1 frame is requested here.
      # Measured at ~300ns/call, caller_locations is the single most
      # expensive thing this hook does -- 4-5x the cost of
      # TracePoint's own dispatch -- and building 2 frames this code
      # never read was pure waste. A unit test proves the single frame
      # from offset 2 still names the exact call site the old 3-frame
      # call's .first used to.
      def build_trace_point(stats)
        TracePoint.new(:call, :return) do |tp|
          begin
            case tp.event
            when :call
              RaiseTracker.instance.push_checkpoint
              caller_loc = caller_locations(2, 1)&.first
              stats.record_call(tp, caller_loc)
            when :return
              # Popped before record_return, not after: even if
              # record_return itself raises (caught below), the
              # checkpoint stack for this fiber is already balanced,
              # so a later call on the same fiber is never thrown off
              # by an earlier one's formatting failure.
              raised = RaiseTracker.instance.pop_and_raised_exit?
              stats.record_return(tp, raised: raised)
            end
          rescue Exception => e # rubocop:disable Lint/RescueException
            # The hook must never let an exception escape into the
            # probed method's own call/return path -- doing so would
            # replace the app's real control flow with one from inside
            # this library. Same rule as Capture's :raise hook.
            warn("bulldogger: probe hook failed: #{e.class}: #{e.message}") if ENV["BULLDOGGER_DEBUG"] == "1"
          end
        end
      end
    end
  end
end
