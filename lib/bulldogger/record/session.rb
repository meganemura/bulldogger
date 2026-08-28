# frozen_string_literal: true

require_relative "../redactor"
require_relative "../formatter"
require_relative "../frame_source"
require_relative "writer"

module Bulldogger
  module Record
    # One recording session: a single TracePoint subscribed to
    # :call/:return/:raise/:rescue, writing :call/:return/:raise as
    # JSONL lines to one trace-NNN.jsonl file.
    #
    # :rescue is subscribed to but never written to the file -- it
    # exists only to feed the raise-exit discriminator (see
    # #on_return); WRITTEN_EVENTS is the actual shipped default the
    # task report measures and docs describe.
    class Session
      WRITTEN_EVENTS = %w[call return raise].freeze

      # A global (non-target) TracePoint is live for the entire
      # process the instant #enable runs -- including the rest of
      # this constructor after that line, and the entry into #stop
      # before it disables anything. Without this filter, every
      # session's trace opened with its own "Session#initialize
      # returned" and "Record.start returned" lines (the latter
      # dumping this session's own Config#inspect -- a value formatter
      # never meant to be part of what a caller asked to observe), and
      # closed with a "Session#stop" call line. Reusing FrameSource's
      # already-measured skip_path_prefix (this library's own lib/
      # directory) filters out bulldogger's own frames the same way
      # Capture already does for :raise.
      SKIP_PATH_PREFIX = Bulldogger::FrameSource.default_skip_path_prefix

      # sink: is an internal seam, not part of the public API a caller
      # is meant to use. Bulldogger::Record.start never passes it; it
      # exists only so the overhead benchmark (test/fixtures/record/
      # bench.rb) can isolate the cost of value capture (TracePoint
      # dispatch, Formatter, Redactor) from the JSONL write that
      # always follows it on the real path -- there is no production
      # code path that captures without writing, so measuring that
      # split needs a substitute writer to exist at all. When sink is
      # given, run_dir is never touched.
      def initialize(config:, run_dir:, sink: nil)
        @config = config
        @enabled = config.enabled && !(run_dir.nil? && sink.nil?)
        return unless @enabled

        @redactor = Redactor.new(config.redact_patterns)
        @formatter = Formatter.new(config: config, redactor: @redactor)
        @writer = sink || Writer.new(run_dir: run_dir, header: header)
        @mutex = Mutex.new
        @sequence = 0
        # Process-wide, not per-thread: it only ever needs to answer
        # "did a raise happen between this frame's :call and its
        # :return", and comparing the DELTA recorded at those two
        # points (not the counter's absolute value at :return alone)
        # makes that answer immune to an imbalance left over from
        # before this particular frame's call started. See the
        # contract's "raise で抜けたときの :return" note: an absolute
        # counter would misclassify a frame if some unrelated raise
        # elsewhere had already left the counter positive when this
        # frame's own :call fired.
        @raise_rescue_counter = 0
        # One call stack per Thread. :call/:return for a given frame
        # always fire on the same thread that made the call, so keying
        # by Thread.current is what lets the delta comparison (and
        # "depth") match each :return to its own :call instead of some
        # other thread's -- a single shared stack would interleave
        # unrelated frames from concurrent threads and pop the wrong
        # entry.
        @call_stacks = Hash.new { |h, k| h[k] = [] }
        # Set just before the real TracePoint#disable call in #stop,
        # and checked first in #handle. Without it: TracePoint#disable
        # is itself a Ruby-level method (its own backtrace names
        # <internal:trace_point>), so calling it while this session's
        # TracePoint is still enabled fires one last :call/:return
        # through this same handler before the disable takes effect --
        # a phantom "TracePoint#disable" line at the end of every
        # trace file (reproduced and confirmed while building this).
        @stopping = false
        # A Thread-local (not tp.disable) reentrancy guard. tp.disable
        # was tried first and rejected: TracePoint's enabled flag is
        # process-wide, so disabling it for the duration of one
        # thread's handler silently drops every other thread's events
        # that happen to fire in that same window -- reproduced with 4
        # threads calling a traced method concurrently, which lost
        # about three-quarters of the expected :call/:return events
        # and corrupted #on_return's per-thread depth bookkeeping for
        # the survivors. A key unique to this Session (not a fixed
        # name) keeps two sessions -- e.g. Record.run nested inside
        # another -- from suppressing each other's events on the same
        # thread.
        @reentrant_key = :"__bulldogger_record_session_#{object_id}__"
        @trace_point = TracePoint.new(:call, :return, :raise, :rescue) { |tp| handle(tp) }
        @trace_point.enable
      end

      # Idempotent, matching Bulldogger.start/stop and Run#finish
      # elsewhere in this codebase: a second call must not re-close an
      # already-closed IO (raises IOError) just because a caller
      # defensively calls #stop from more than one place (an ensure
      # block after an earlier explicit call, for example).
      def stop
        return nil unless @enabled
        return @result_path if @stopping

        @stopping = true
        @trace_point.disable
        @result_path = @writer.close
      end

      private

      def header
        {
          "schema_version" => 1,
          "kind" => "record",
          "started_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
          "events" => WRITTEN_EVENTS,
          "limits" => { "max_value_length" => @config.max_value_length }
        }
      end

      def handle(tp)
        return if @stopping
        # Filters out this library's own frames (Session, Writer,
        # Formatter, Redactor all live under the same lib/ tree), so
        # the recursion guard below only has to catch the case that
        # filter cannot: formatting a value calls #inspect on
        # whatever the app passed in, and an app-defined #inspect
        # override is Ruby code outside this prefix.
        return if tp.path&.start_with?(SKIP_PATH_PREFIX)
        # Thread-local, not tp.disable (see @reentrant_key above): this
        # only needs to stop the current thread's own call chain from
        # recursing into itself (Formatter calling an app object's
        # #inspect, which itself fires a new :call this same handler
        # would otherwise try to process); it must not touch any other
        # thread's visibility into the trace point at all.
        return if Thread.current[@reentrant_key]

        Thread.current[@reentrant_key] = true
        begin
          dispatch(tp)
        ensure
          Thread.current[@reentrant_key] = false
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        # Same rule as Capture's :raise hook (contract.md): a recorder
        # must never be the reason the traced code fails.
        warn("bulldogger: record failed: #{e.class}: #{e.message}") if debug?
        nil
      end

      def dispatch(tp)
        case tp.event
        when :call then on_call(tp)
        when :return then on_return(tp)
        when :raise then on_raise(tp)
        when :rescue then on_rescue(tp)
        end
      end

      def on_call(tp)
        @mutex.synchronize do
          stack = @call_stacks[Thread.current]
          stack.push(@raise_rescue_counter)
          @sequence += 1
          @writer.write_event(build_call_event(tp, @sequence, stack.size))
        end
      end

      def on_return(tp)
        @mutex.synchronize do
          stack = @call_stacks[Thread.current]
          counter_at_call = stack.last
          depth = stack.size
          raised = !counter_at_call.nil? && (@raise_rescue_counter - counter_at_call).positive?
          stack.pop
          @call_stacks.delete(Thread.current) if stack.empty?
          @sequence += 1
          @writer.write_event(build_return_event(tp, @sequence, depth, raised))
        end
      end

      def on_raise(tp)
        @mutex.synchronize do
          @raise_rescue_counter += 1
          @sequence += 1
          depth = @call_stacks[Thread.current].size
          @writer.write_event(build_raise_event(tp, @sequence, depth))
        end
      end

      # Not written to the trace (see WRITTEN_EVENTS); this only feeds
      # the -1 half of the raise/rescue delta #on_return reads. Covers
      # Ruby-level rescue only (Feature #19572, landed in 3.3.0) -- a
      # C-level exception path such as Integer(s, exception: false)
      # never fires :raise in the first place, so it cannot leave this
      # counter unbalanced.
      def on_rescue(_tp)
        @mutex.synchronize { @raise_rescue_counter -= 1 }
      end

      def build_call_event(tp, seq, depth)
        {
          "event" => "call",
          "seq" => seq,
          "depth" => depth,
          "path" => tp.path,
          "line" => tp.lineno,
          "method" => method_label(tp),
          "args" => build_args(tp)
        }
      end

      def build_return_event(tp, seq, depth, raised)
        event = {
          "event" => "return",
          "seq" => seq,
          "depth" => depth,
          "path" => tp.path,
          "line" => tp.lineno,
          "method" => method_label(tp)
        }
        # tp.return_value raises RuntimeError on any event but :return
        # (measured; contract-verbs.md), and reading it at all when the
        # method actually exited via raise would report a nil the
        # method never returned -- the exact trap this discriminator
        # exists to avoid, so the branch below never touches it when
        # raised is true.
        if raised
          event["raised"] = true
        else
          event["return"] = @formatter.format(tp.return_value)
        end
        event
      end

      def build_raise_event(tp, seq, depth)
        {
          "event" => "raise",
          "seq" => seq,
          "depth" => depth,
          "path" => tp.path,
          "line" => tp.lineno,
          "method" => method_label(tp),
          "exception" => exception_section(tp.raised_exception)
        }
      end

      def exception_section(exception)
        message = exception.message.to_s
        limit = @config.max_value_length * 5
        section = {
          "class" => exception_class_name(exception),
          "message" => message.length > limit ? "#{message[0, limit]}…" : message
        }
        if message.length > limit
          section["message_truncated"] = true
          section["message_original_length"] = message.length
        end
        section
      end

      def exception_class_name(exception)
        exception.class.name || exception.class.to_s
      rescue Exception # rubocop:disable Lint/RescueException
        "Object"
      end

      # At :call, tp.binding.local_variables holds exactly the
      # parameters -- including omitted optional/keyword ones already
      # filled with their default (measured: an omitted `discount:`
      # showed as nil, not absent) -- so this is the actual-arguments
      # read the contract calls for, not a later snapshot of whatever
      # the method body has reassigned by :return time.
      def build_args(tp)
        binding = tp.binding
        return {} unless binding

        tp.parameters.each_with_object({}) do |(_kind, name), args|
          next unless name # anonymous *, **, & params carry no name to look up

          args[name.to_s] = build_value_entry(name, binding)
        end
      end

      def build_value_entry(name, binding)
        return { "redacted" => true, "reason" => "name" } if @redactor.redact_name?(name)

        @formatter.format(binding.local_variable_get(name))
      end

      # "Klass#method" for an instance method, "Klass.method" for a
      # class/singleton method. attached_object recovers the real
      # owner name from tp.defined_class's singleton class; without it
      # a class method would render as "#<Class:Klass>", which a
      # reader has no use for. No respond_to? guard: singleton_class?
      # and attached_object are both guaranteed on every Ruby this gem
      # accepts (>= 4.0; attached_object landed in 3.2). The rescue
      # below covers the real runtime edge case instead --
      # attached_object raises TypeError for a singleton class with no
      # attached object, e.g. nil/true/false's.
      def method_label(tp)
        klass = tp.defined_class
        if klass.singleton_class?
          "#{klass.attached_object}.#{tp.method_id}"
        else
          "#{klass}##{tp.method_id}"
        end
      rescue Exception # rubocop:disable Lint/RescueException
        tp.method_id.to_s
      end

      def debug?
        ENV["BULLDOGGER_DEBUG"] == "1"
      end
    end
  end
end
