# frozen_string_literal: true

# Bench harness for the AGENTS.md overhead claims ("costs nothing
# while green", "microseconds per exception when they are not"). Not
# a minitest/rspec suite on purpose: the number this needs is the
# workload loop's own time, not ruby-plus-gems boot time, and a real
# test framework's reporter would only add noise to that measurement.
#
# ARGV: mode ("raise_free" | "rescue_heavy" | "red"), toggle ("on" | "off")
# Prints one line: "BULLDOGGER_BENCH_ELAPSED: <seconds>"

require "tmpdir"

mode, toggle = ARGV
on = toggle == "on"

if on
  require "bulldogger"
  Bulldogger.config.output_dir = Dir.mktmpdir("bulldogger-bench-")
  Bulldogger.start
end

RAISE_FREE_ITERATIONS = 2_000_000
RESCUE_HEAVY_ITERATIONS = 10_000
RED_ITERATIONS = 200

workload = case mode
           when "raise_free"
             -> { RAISE_FREE_ITERATIONS.times { |i| i * 2 } }
           when "rescue_heavy"
             lambda {
               RESCUE_HEAVY_ITERATIONS.times do |i|
                 raise "boom #{i}"
               rescue RuntimeError
                 nil
               end
             }
           when "red"
             lambda {
               RED_ITERATIONS.times do |i|
                 raise ArgumentError, "boom #{i}"
               rescue ArgumentError => e
                 Bulldogger.record_failure(exception: e, test: { framework: "bench", id: "bench##{i}", file: __FILE__, line: __LINE__ }) if on
               end
             }
           else
             raise ArgumentError, "unknown mode: #{mode.inspect}"
           end

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
workload.call
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

Bulldogger.finish if on

puts "BULLDOGGER_BENCH_ELAPSED: #{elapsed}"
