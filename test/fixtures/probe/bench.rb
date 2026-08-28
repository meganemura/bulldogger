# frozen_string_literal: true

# Bench harness for probe's per-call overhead. Not a minitest/rspec
# suite on purpose, matching test/fixtures/overhead/bench.rb: the
# number that matters is the workload loop's own time, not process
# boot time. There is no pass/fail ratio here -- probe carries four
# per-call requirements (argument shape, return shape, callers, raise
# exits), and the absolute ns/call this prints is what gets published,
# not compared against a fixed band.
#
# ARGV: workload ("trivial" | "realistic"), condition ("off" | "on" | "bare")
# "off" never loads bulldogger. "on" wraps the workload in a real
# Bulldogger.probe session. "bare" wraps it in a TracePoint(:call,
# :return, target:) whose block does nothing -- the floor no
# implementation can beat, since it is Ruby's own dispatch cost for a
# *targeting* TracePoint, before a single line of this library runs.
# Prints one line: "BULLDOGGER_BENCH_ELAPSED: <seconds>"

require "tmpdir"

workload_name, condition = ARGV

class TrivialTarget
  def work(x)
    x + 1
  end
end

class RealisticTarget
  # A little real work per call (arithmetic plus a Hash and a String)
  # -- "call-dense" per the contract's own phrase means called often,
  # not that the call itself does nothing; a method that does nothing
  # makes *any* fixed per-call cost look unbounded in relative terms,
  # which is a property of the workload, not of what is added to it.
  def work(order_id, qty)
    total = qty * 10
    { order_id: order_id, total: total, label: "order-#{order_id}" }
  end
end

case workload_name
when "trivial"
  target_class = TrivialTarget
  target_label = "TrivialTarget#work"
  iterations = 500_000
  call_workload = ->(target) { iterations.times { |i| target.work(i) } }
when "realistic"
  target_class = RealisticTarget
  target_label = "RealisticTarget#work"
  iterations = 200_000
  call_workload = ->(target) { iterations.times { |i| target.work(i, i % 7) } }
else
  raise ArgumentError, "unknown workload: #{workload_name.inspect}"
end

target = target_class.new

case condition
when "off"
  # nothing to set up
when "on"
  require "bulldogger"
  Bulldogger.config.output_dir = Dir.mktmpdir("bulldogger-probe-bench-")
when "bare"
  unbound_method = target_class.instance_method(:work)
  tp = TracePoint.new(:call, :return) { |_t| nil }
  tp.enable(target: unbound_method)
else
  raise ArgumentError, "unknown condition: #{condition.inspect}"
end

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
case condition
when "on"
  Bulldogger.probe(target_label) { call_workload.call(target) }
else
  call_workload.call(target)
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

puts "BULLDOGGER_BENCH_ELAPSED: #{elapsed}"
