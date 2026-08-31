# frozen_string_literal: true

require_relative "redactor"
require_relative "formatter"
require_relative "frame_source"
require_relative "pending"

module Bulldogger
  # Subscribes to :raise globally and turns every raised exception into
  # a bounded, already-serialized snapshot before the hook returns.
  #
  # Serialization happens here, inside the hook, rather than later from
  # whatever holds the frame data: a DEBUGGER__::FrameInfo keeps its
  # frame's Binding alive, and a live Binding keeps every object
  # reachable from that frame alive too (measured: the TracePoint
  # block's own captured-array local was still reachable through a
  # retained Binding). Rendering every value to a String and dropping
  # the FrameInfo/Binding before this method returns is what makes the
  # Pending ring's size an actual memory bound, not just a count of
  # references to unbounded object graphs.
  class Capture
    def initialize(config:)
      @config = config
      @redactor = Redactor.new(config.redact_patterns)
      @formatter = Formatter.new(config: config, redactor: @redactor)
      @frame_source = FrameSource.new(config: config, formatter: @formatter, redactor: @redactor)
      @pending = Pending.new(config.max_pending)
      @trace_point = nil
      @start_mutex = Mutex.new
      @raise_count = 0
      @checkpoint = nil
    end

    def start
      @start_mutex.synchronize do
        return self if @trace_point

        @frame_source.resolve!
        trace_point = TracePoint.new(:raise) { |tp| handle_raise(tp) }
        trace_point.enable
        @trace_point = trace_point
      end
      self
    end

    def stop
      @start_mutex.synchronize do
        @trace_point&.disable
        @trace_point = nil
      end
      self
    end

    def running?
      !@trace_point.nil?
    end

    def snapshot_for(exception)
      @pending.get(exception)
    end

    def begin_test
      @checkpoint = @raise_count
      self
    end

    def end_test
      @checkpoint = nil
      self
    end

    def reason_for_missing(exception)
      return "capture_disabled" unless running?
      return "evicted" if @pending.evicted?(exception)

      "not_captured"
    end

    private

    # :raise fires for every exception, including ones the app rescues
    # and handles without incident. This hook must never let an
    # exception escape: doing so would replace the app's real raise
    # with one from inside our own hook, corrupting the very failure
    # the app was raising. `rescue Exception`, not `StandardError`,
    # because even a NoMemoryError or SystemStackError surfacing from
    # our own code here must not propagate into the app's raise path.
    def handle_raise(tp)
      @raise_count += 1
      exception = tp.raised_exception
      frames, frames_omitted = @frame_source.capture(tp)
      snapshot = {
        "capture_mode" => @frame_source.mode.to_s,
        "frames" => frames,
        "raise_ordinal" => @checkpoint && @raise_count - @checkpoint
      }
      # frames_omitted only appears when something was actually cut, so
      # its presence alone tells a reader "frames were dropped here" --
      # the same rule build_frame already applies to locals_omitted.
      snapshot["frames_omitted"] = frames_omitted if frames_omitted.positive?
      @pending.put(exception, snapshot)
      nil
    rescue Exception => e # rubocop:disable Lint/RescueException
      warn("bulldogger: capture failed: #{e.class}: #{e.message}") if debug?
      nil
    end

    def debug?
      ENV["BULLDOGGER_DEBUG"] == "1"
    end
  end
end
