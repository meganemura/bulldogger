# frozen_string_literal: true

require_relative "bucket"

module Bulldogger
  module Probe
    # Aggregates every :call/:return pair observed for one probe
    # target into the "methods"[label] shape the evidence JSON
    # publishes: call count, per-parameter and return-value shape, the
    # raise-exit count, and the set of call sites.
    #
    # record_call/record_return take no lock: each caller writes only
    # into its own ThreadLocal (below), reached through Thread.current[]
    # -- fiber-local, like RaiseTracker's own storage, so two fibers on
    # the same OS thread still get separate slots -- keyed uniquely to
    # this MethodStats instance, so two threads calling the same probed
    # method concurrently never touch the same mutable state. A per-call
    # Mutex#synchronize was measured to be on the hot path for every
    # single call and return; a fiber only pays a lock once -- the first
    # time it is ever seen by this target, to register its ThreadLocal
    # in @locals -- and #to_h folds every one of them into the published
    # totals exactly once, at finish time.
    class MethodStats
      # One fiber's own, lock-free view of this target. Merged into
      # the instance's published totals by #merge_local, once, in
      # #to_h.
      ThreadLocal = Struct.new(:calls, :raised_exits, :param_buckets, :returns, :raised, :callers)

      def initialize(target:, formatter:, redactor:, max_samples:)
        @formatter = formatter
        @redactor = redactor
        @max_samples = max_samples
        @parameters = declared_parameters(target.unbound_method)

        @calls = 0
        @raised_exits = 0
        @param_buckets = build_param_buckets
        @returns = new_returns_bucket
        @raised = Hash.new(0)
        # key => [count, one representative Thread::Backtrace::Location].
        # One Hash, not two: a second hash keyed the same way would be
        # a second lookup on every single call for no benefit -- see
        # #record_caller.
        @callers = {}

        # Unique per instance (not a fixed name): two targets probed
        # in the same session must not share one thread-local slot.
        @thread_key = :"bulldogger_probe_method_stats_#{object_id}"
        @locals = []
        @locals_mutex = Mutex.new
        @merge_mutex = Mutex.new
        @merged = false
      end

      def record_call(tp, caller_location)
        local = thread_local
        local.calls += 1
        record_param_samples(local, tp.binding)
        record_caller(local, caller_location)
      end

      # raised: true means contract-verbs.md's raise-exit discriminator
      # fired for this return -- this call must not be counted as a
      # nil return (that would fabricate a "returned nil" the method
      # never actually did), so it updates the thread-local @raised
      # instead of @returns and never touches the returns bucket at
      # all.
      def record_return(tp, raised:)
        local = thread_local
        if raised
          local.raised_exits += 1
          klass = RaiseTracker.instance.current_exception_class_name || "Object"
          local.raised[klass] += 1
        else
          local.returns.record(tp.return_value)
        end
      end

      def to_h
        merge!
        {
          "calls" => @calls,
          "raised_exits" => @raised_exits,
          "parameters" => @parameters,
          "params" => params_to_h,
          "returns" => @returns.to_h,
          "raised" => @raised,
          "callers" => callers_to_h
        }
      end

      private

      # UnboundMethod#parameters is declared, static shape -- computed
      # once here, not derived from tp.parameters per call, since it
      # cannot change between calls and re-deriving it every time would
      # only add cost with no new information.
      def declared_parameters(unbound_method)
        unbound_method.parameters.map { |kind, name| [kind.to_s, name&.to_s] }
      end

      def build_param_buckets
        @parameters.each_with_object({}) do |(_kind, name), buckets|
          next if name.nil? # anonymous *, **, or & has no bindable local to sample

          buckets[name] = Bucket.new(formatter: @formatter, max_samples: @max_samples,
                                      redacted_name: @redactor.redact_name?(name))
        end
      end

      def new_returns_bucket
        Bucket.new(formatter: @formatter, max_samples: @max_samples)
      end

      # Lazily creates and registers this fiber's ThreadLocal on
      # first touch. @locals_mutex is taken only here -- once per
      # fiber per target, not once per call -- to append to the
      # shared registry that #merge! later reads.
      def thread_local
        Thread.current[@thread_key] ||= begin
          local = ThreadLocal.new(0, 0, build_param_buckets, new_returns_bucket, Hash.new(0), {})
          @locals_mutex.synchronize { @locals << local }
          local
        end
      end

      def record_param_samples(local, binding)
        local.param_buckets.each do |name, bucket|
          bucket.record(binding.local_variable_get(name.to_sym))
        end
      end

      # Tallies by a "path:lineno" String built from two cheap
      # attribute reads, not by Location#to_s (which additionally
      # resolves and formats a method label on every single call).
      # Measured directly: this key plus one Hash lookup costs about
      # half of the old to_s-keyed lookup. An Array key ([path,
      # lineno]) was tried first and measured *slower* than the
      # to_s baseline it was meant to beat -- Array#hash and #eql?
      # walk and hash every element on every lookup, so a compound
      # object is not automatically a cheap Hash key. A String is.
      #
      # One Hash lookup, not two: the value is a mutable [count,
      # location] pair, so an existing entry is updated in place
      # (cheap, no second Hash op) and only a first-time key pays for
      # a Hash write. The full "path:line:in 'label'" String -- what
      # the evidence actually publishes -- is built from the stored
      # Location at most once per distinct call site, in
      # #callers_to_h, not once per call.
      def record_caller(local, caller_location)
        return unless caller_location

        key = "#{caller_location.path}:#{caller_location.lineno}"
        entry = local.callers[key]
        if entry
          entry[0] += 1
        else
          local.callers[key] = [1, caller_location]
        end
      end

      # Runs once, the first time #to_h is called: folds every
      # fiber's ThreadLocal into the published totals under
      # @merge_mutex, so #to_h itself can be called more than once
      # (Writer calls it exactly once per target today) without
      # double-counting.
      def merge!
        return if @merged

        @merge_mutex.synchronize do
          return if @merged

          # Snapshot under @locals_mutex, then merge outside it: a
          # fiber could still be registering its own ThreadLocal
          # (the append in #thread_local) concurrently with finish, so
          # the read of @locals itself needs the same lock the writer
          # uses, even though the per-call recording above never does.
          locals = @locals_mutex.synchronize { @locals.dup }
          locals.each { |local| merge_local(local) }
          @merged = true
        end
      end

      def merge_local(local)
        @calls += local.calls
        @raised_exits += local.raised_exits
        local.param_buckets.each { |name, bucket| @param_buckets[name].merge!(bucket) }
        @returns.merge!(local.returns)
        local.raised.each { |klass, count| @raised[klass] += count }
        local.callers.each do |key, (count, location)|
          entry = @callers[key]
          if entry
            entry[0] += count
          else
            @callers[key] = [count, location]
          end
        end
      end

      def params_to_h
        @param_buckets.transform_values(&:to_h)
      end

      # Location#to_s (the "path:line:in 'label'" format the evidence
      # publishes) runs here, once per distinct call site total across
      # every fiber -- not once per call, which is what made this the
      # single most expensive part of the hook before this task.
      def callers_to_h
        @callers.each_with_object({}) do |(_key, (count, location)), result|
          result[location.to_s] = count
        end
      end
    end
  end
end
