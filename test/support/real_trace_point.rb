# frozen_string_literal: true

module Bulldogger
  module TestSupport
    # A stand-in for a live TracePoint, used by unit tests that call a
    # hook-internal method directly (outside any TracePoint) so stdlib
    # Coverage can see the lines run -- Coverage cannot observe a line
    # executing while a TracePoint callback is already on the stack
    # (see test/unit/tracepoint_coverage_blind_spot_test.rb).
    #
    # Every TracePoint attribute reader (#binding, #self, #path,
    # #lineno, #method_id, #defined_class, #parameters,
    # #raised_exception, #return_value) raises RuntimeError ("access
    # from outside") the instant the callback that received the
    # object returns -- measured directly while building this file. A
    # double built from invented values would risk disagreeing with
    # what a real TracePoint actually reports for a given event; this
    # one only replays values a real TracePoint already produced,
    # captured while a real, throwaway TracePoint's own callback was
    # still live.
    #
    # A field a real TracePoint would refuse for the wrong event (e.g.
    # #return_value during a :call) is simply nil here rather than
    # raising: nothing under test reads a field outside the event it
    # belongs to, so the stricter real behavior has nothing to guard
    # against in practice.
    Double = Struct.new(:event, :path, :lineno, :method_id, :defined_class, :parameters,
                         :binding, :self, :raised_exception, :return_value, keyword_init: true)

    module_function

    # Runs block, which must raise exactly once, and returns a Double
    # built from the real :raise event's own attributes -- the shape
    # Capture#handle_raise and FrameSource's degraded-mode methods
    # receive.
    def capture_raise
      double = nil
      tp = TracePoint.new(:raise) do |t|
        double = Double.new(event: t.event, path: t.path, lineno: t.lineno, method_id: t.method_id,
                             defined_class: t.defined_class, binding: t.binding, self: t.self,
                             raised_exception: t.raised_exception)
      end
      tp.enable
      begin
        yield
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      ensure
        tp.disable
      end
      raise "capture_raise: block did not raise" if double.nil?

      double
    end

    # Runs block, which must call target_method (an UnboundMethod)
    # exactly once, and returns [call_double, return_double] built
    # from the real :call/:return events for that one invocation --
    # the shape Probe::Session's dispatch, Probe::MethodStats, and
    # Record::Session's on_call/on_return/build_*_event methods
    # receive.
    def capture_call_and_return(target_method)
      call_double = nil
      return_double = nil
      tp = TracePoint.new(:call, :return) do |t|
        case t.event
        when :call
          call_double = Double.new(event: t.event, path: t.path, lineno: t.lineno, method_id: t.method_id,
                                    defined_class: t.defined_class, parameters: t.parameters, binding: t.binding,
                                    self: t.self)
        when :return
          return_double = Double.new(event: t.event, path: t.path, lineno: t.lineno, method_id: t.method_id,
                                      defined_class: t.defined_class, parameters: t.parameters, binding: t.binding,
                                      self: t.self, return_value: t.return_value)
        end
      end
      tp.enable(target: target_method)
      begin
        yield
      ensure
        tp.disable
      end
      raise "capture_call_and_return: block did not call the target method" if call_double.nil? || return_double.nil?

      [call_double, return_double]
    end
  end
end
