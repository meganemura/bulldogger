# frozen_string_literal: true

# Bench harness for the probe/record proportionality law
# (contract-verbs.md's "probe の性能条件": probe's cost scales with
# calls to the targeted method M, record's with total calls N). Drives
# Proportionality::App#step target_calls + other_calls times, routing
# to Target#hit exactly target_calls times and Other#noise exactly
# other_calls times, interleaved so neither TracePoint sees a long
# uniform run of only one method.
#
# The driving loop lives here, not in app.rb, on purpose: a wrapper
# method around it would itself be a Ruby-level call record's
# process-wide TracePoint would also see, adding a call this bench
# does not mean to measure. Top-level script code generates no :call
# event, so only App#step/Target#hit/Other#noise ever do.
#
# Two more sources of an uncounted call were found and removed by
# checking the actual JSONL record wrote, not assumed away:
# `Proportionality::App.new` (and the Target/Other it constructs) is
# built before any mode's tracing/probing starts, and the drive loop
# below is a `while`, not `Integer#times` -- `#times` is itself a
# genuine Ruby-level method (defined in Ruby's own
# `<internal:numeric>` prelude; h-record.md documents this the same
# way), so its block form would add one more :call/:return pair that
# has nothing to do with target_calls or other_calls.
#
# ARGV: mode ("baseline" | "probe" | "record"), target_calls, other_calls
# Prints:
#   BULLDOGGER_BENCH_ELAPSED: <seconds>
#   BULLDOGGER_BENCH_FIXTURE_M: <int>   -- Target#hit calls, fixture-counted
#   BULLDOGGER_BENCH_FIXTURE_N: <int>   -- every call, fixture-counted
#   BULLDOGGER_BENCH_ARTIFACT_M: <int>  -- probe mode only: read back from
#                                          the written evidence JSON
#   BULLDOGGER_BENCH_ARTIFACT_N: <int>  -- record mode only: "call" lines
#                                          counted in the written JSONL

require "tmpdir"
require "json"
require_relative "app"

mode = ARGV[0]
target_calls = Integer(ARGV[1])
other_calls = Integer(ARGV[2])

path = nil
record_session = nil

# Built before any mode enables tracing/probing, so the constructors
# themselves never appear as events -- see the note above.
app = Proportionality::App.new
total = target_calls + other_calls

case mode
when "baseline"
  # nothing to set up
when "probe"
  require "bulldogger"
  Bulldogger.config.output_dir = Dir.mktmpdir("bulldogger-proportionality-bench-")
when "record"
  require "bulldogger/record"
  Bulldogger.config.output_dir = Dir.mktmpdir("bulldogger-proportionality-bench-")
  record_session = Bulldogger::Record.start
else
  raise ArgumentError, "unknown mode: #{mode.inspect}"
end

drive = lambda do
  i = 0
  hits_so_far = 0
  while i < total
    want_hit = ((i + 1) * target_calls) > (hits_so_far * total)
    app.step(i, hit: want_hit)
    hits_so_far += 1 if want_hit
    i += 1
  end
end

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
case mode
when "probe"
  path = Bulldogger.probe("Proportionality::Target#hit") { drive.call }
else
  drive.call
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

path = record_session.stop if mode == "record"

fixture_m = app.target.calls
fixture_n = app.calls + app.target.calls + app.other.calls

puts "BULLDOGGER_BENCH_ELAPSED: #{elapsed}"
puts "BULLDOGGER_BENCH_FIXTURE_M: #{fixture_m}"
puts "BULLDOGGER_BENCH_FIXTURE_N: #{fixture_n}"

if mode == "probe"
  evidence = JSON.parse(File.read(path))
  artifact_m = evidence.dig("methods", "Proportionality::Target#hit", "calls")
  puts "BULLDOGGER_BENCH_ARTIFACT_M: #{artifact_m}"
elsif mode == "record"
  artifact_n = File.foreach(path).count { |line| line.include?('"event":"call"') }
  puts "BULLDOGGER_BENCH_ARTIFACT_N: #{artifact_n}"
end
