# frozen_string_literal: true

# Mirrors lib/bulldogger/exec_collector.rb's shape: a global :call/:return
# gate (always enabled, filters by method name), and -- once the target
# method is entered -- a second TracePoint scoped to that one ISeq via
# `enable(target:)`, whose :line callback evaluates a statement in the
# traced binding and then disables itself.
#
# VARIANT env var selects where the targeted TracePoint gets disabled:
#   "a" (default) -- inside its own :line callback, the shape
#       exec_collector.rb's `evaluate` method used before its fix.
#   "b" -- deferred: the :line callback only sets a flag; the outer
#       :return event (a separate TracePoint firing, not the one whose
#       list is mid-dispatch) does the actual disable. This is the
#       shape exec_collector.rb's `leave` method uses now.
VARIANT = ENV.fetch("REPRO_VARIANT", "a")
TARGET_METHOD = :target
# 11 is target.rb's bare `result` return line; see its own header comment.
TARGET_LINE = ENV.fetch("REPRO_TARGET_LINE", "11").to_i

line_trace = nil
evaluated = false

gate = TracePoint.new(:call, :return) do |trace|
  next unless trace.method_id == TARGET_METHOD

  if trace.event == :call
    if line_trace.nil? && !evaluated
      iseq = RubyVM::InstructionSequence.of(trace.binding.eval("method(__method__)"))
      line_trace = TracePoint.new(:line) do |line_event|
        next unless line_event.lineno == TARGET_LINE
        next if evaluated

        line_event.binding.eval("result")
        evaluated = true

        if VARIANT == "a"
          line_trace.disable
          line_trace = nil
        end
      end
      line_trace.enable(target: iseq)
    end
  elsif VARIANT == "b" && evaluated && line_trace
    line_trace.disable
    line_trace = nil
  end
end
gate.enable
