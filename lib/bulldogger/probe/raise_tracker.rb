# frozen_string_literal: true

module Bulldogger
  module Probe
    # Tells a probed method's normal return apart from a raise-exit.
    # `:call`/`:return` can be targeted to one method, but `:raise`
    # cannot (measured in contract-verbs.md): it fires globally, for
    # every exception in the process. Distinguishing "returned nil"
    # from "exited by raising" needs this second, global signal,
    # correlated with each targeted call through the checkpoint below.
    #
    # Mechanism (contract-verbs.md, measured on ruby 4.0.6): a global
    # counter that a `:raise` TracePoint increments and a `:rescue`
    # TracePoint decrements. `:call` records the counter's value; at
    # `:return`, a *positive delta* from that recorded value means an
    # exception passed through this frame's unwind between the two
    # events, because the caller's own `:rescue` fires only after
    # `:return`, so the counter is still unbalanced at `:return` time.
    #
    # Delta, not the absolute counter: an absolute counter left
    # unbalanced by a raise from *before* this call started (e.g. one
    # whose `:rescue` fires after this session already released the
    # tracker) would poison every later call on the same fiber. A
    # delta only asks "did the counter move during *this* call", so a
    # pre-existing imbalance cannot produce a false positive.
    #
    # Counter and checkpoint stack are fiber-local (Thread.current[]),
    # not a single shared integer: a fiber's call stack is private to
    # that fiber, and only one exception can be unwinding through a
    # given fiber's stack at a time, so a fiber-local counter can
    # never be perturbed by an unrelated raise on another fiber or
    # thread. A single shared counter would not have that guarantee.
    #
    # `:rescue` requires ruby >= 3.3.0 (Feature #19572); this gem's
    # required_ruby_version is >= 4.0, so no degrade path is needed
    # here. `:rescue` only fires for Ruby-level `rescue` (ruby's own
    # NEWS-3.3.0.md); a raise fully handled inside C code (measured:
    # `Integer(s, exception: false)`) never fires `:raise` either, so
    # it cannot unbalance the counter in the first place.
    class RaiseTracker
      COUNTER_KEY = :bulldogger_probe_raise_counter
      STACK_KEY = :bulldogger_probe_raise_checkpoints
      CLASS_KEY = :bulldogger_probe_raise_class

      def self.instance
        @instance ||= new
      end

      def initialize
        @mutex = Mutex.new
        @refcount = 0
        @raise_tp = nil
        @rescue_tp = nil
      end

      # Ref-counted: multiple probe sessions can be active at once
      # (different targets, or nested probe calls) and all of them
      # need this same pair of TracePoints running, but each pays only
      # its own targeted :call/:return cost -- the untargeted :raise/
      # :rescue subscription is shared, not duplicated per session.
      def acquire
        @mutex.synchronize do
          @refcount += 1
          next unless @refcount == 1

          @raise_tp = TracePoint.new(:raise) { |tp| on_raise(tp) }
          @rescue_tp = TracePoint.new(:rescue) { on_rescue }
          @raise_tp.enable
          @rescue_tp.enable
        end
      end

      def release
        @mutex.synchronize do
          @refcount -= 1
          next if @refcount.positive?

          @raise_tp&.disable
          @rescue_tp&.disable
          @raise_tp = nil
          @rescue_tp = nil
        end
      end

      # Call at :call time, before any work that could raise inside
      # the hook itself -- a cheap Array#push that must not be skipped,
      # or the matching pop_and_raised_exit? at :return would read the
      # wrong checkpoint and desynchronize every later call on this
      # fiber.
      def push_checkpoint
        (Thread.current[STACK_KEY] ||= []) << counter
      end

      # Call at :return time. Pops the checkpoint pushed by the
      # matching push_checkpoint (calls on one fiber nest properly, so
      # a plain stack -- not a per-target slot -- keeps recursive and
      # interleaved targets correctly paired) and reports whether the
      # counter moved since that call started.
      def pop_and_raised_exit?
        stack = Thread.current[STACK_KEY]
        checkpoint = stack && !stack.empty? ? stack.pop : 0
        counter > checkpoint
      end

      # Only meaningful right after pop_and_raised_exit? returned
      # true: the class of the most recent :raise seen on this fiber,
      # which is the exception currently unwinding through the
      # caller's frame. Stale otherwise; callers must gate on
      # pop_and_raised_exit?, not read this unconditionally.
      def current_exception_class_name
        Thread.current[CLASS_KEY]
      end

      private

      def counter
        Thread.current[COUNTER_KEY] || 0
      end

      def on_raise(tp)
        Thread.current[COUNTER_KEY] = counter + 1
        Thread.current[CLASS_KEY] = exception_class_name(tp.raised_exception)
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end

      def on_rescue
        Thread.current[COUNTER_KEY] = counter - 1
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end

      def exception_class_name(exception)
        klass = exception.class
        klass.respond_to?(:name) ? (klass.name || klass.to_s) : klass.to_s
      rescue Exception # rubocop:disable Lint/RescueException
        "Object"
      end
    end
  end
end
