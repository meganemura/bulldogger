# frozen_string_literal: true

# Standalone reproduction of a Ruby VM segfault found while running this
# gem's own `rake coverage` task. No bulldogger code is involved -- this
# is three stdlib/language features stacked together:
#
#   1. stdlib Coverage running (Coverage.start(lines: true))
#   2. a global TracePoint on :call/:return, always enabled
#   3. a second TracePoint scoped to one ISeq via `enable(target:)`,
#      created from inside the global callback once the target method
#      is entered
#
# REPRO_VARIANT selects where the scoped TracePoint gets disabled
# (see collector.rb):
#   "a" (default) -- inside its own :line callback.
#   "b" -- deferred to the global TracePoint's :return callback instead.
#
# Run:
#   REPRO_VARIANT=a ruby boot.rb   # crashes on roughly half of runs
#   REPRO_VARIANT=b ruby boot.rb   # 0/50 crashes in repeated local runs
#
# Observed (ruby 4.0.6, 2026-07-14 revision 03b6d3f889, +PRISM,
# arm64-darwin25), variant "a":
#
#   target.rb:11: [BUG] Segmentation fault at 0x...
#   -- C level backtrace information --
#   .../libruby.4.0.dylib(exec_hooks_protected+0xa0)
#   .../libruby.4.0.dylib(rb_exec_event_hooks+0x7c)
#   .../libruby.4.0.dylib(vm_trace_hook+0x198)
#   .../libruby.4.0.dylib(vm_trace+0x290)
#
# This is the same crash site, with the same three-features-stacked
# shape, that `rake coverage` hits when running
# test/fixtures/exec/minitest_exec_test.rb through
# lib/bulldogger/exec_collector.rb: a TracePoint(target: iseq) whose
# own :line callback disables itself, on an ISeq that stdlib Coverage
# is also instrumenting. bulldogger's own fix (see exec_collector.rb's
# `leave` method) is variant "b": defer the disable to a separate,
# already-active TracePoint's callback, never to the firing
# TracePoint's own callback.
require "coverage"
Coverage.start(lines: true)
require_relative "collector"
require_relative "target"
