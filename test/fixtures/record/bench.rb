# frozen_string_literal: true

# Bench harness for Record's overhead claim (contract-verbs.md
# "record のコスト"): an explicit, heavy verb, never the always-on
# trace AGENTS.md's design principles close the door on. Not a
# minitest/rspec suite for the same reason bench.rb (the
# failure-capture bench) is not one: only the workload loop's own time
# matters, and a real test framework's reporter would only add noise.
#
# ARGV: tier ("baseline" | "capture_only" | "full")
# Prints one line: "BULLDOGGER_BENCH_ELAPSED: <seconds>"

require "tmpdir"

tier = ARGV[0]
ITERATIONS = 20_000

module Workload
  def self.inner(qty, rows = [1, 2, 3])
    qty + rows.sum
  end

  def self.outer(i)
    inner(i)
  rescue StandardError
    nil
  end
end

session = nil

case tier
when "baseline"
  # No Bulldogger involvement at all: this is the number "capture_only"
  # and "full" are a multiple of.
when "capture_only"
  require "bulldogger/record"

  # An internal seam (Session#sink), not part of the documented public
  # API (Bulldogger::Record.start never passes it). It exists only so
  # this bench can isolate the cost of value capture -- TracePoint
  # dispatch, Formatter, Redactor, the per-thread call-stack/counter
  # bookkeeping -- from the JSONL write that always follows it on the
  # real path. There is no production code path that captures without
  # writing, so measuring that split needs a substitute writer.
  class NullSink
    def write_event(_event); end
    def close; end
  end

  session = Bulldogger::Record::Session.new(config: Bulldogger.config, run_dir: nil, sink: NullSink.new)
when "full"
  require "bulldogger/record"
  Bulldogger.config.output_dir = Dir.mktmpdir("bulldogger-record-bench-")
  session = Bulldogger::Record.start
else
  raise ArgumentError, "unknown tier: #{tier.inspect}"
end

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ITERATIONS.times { |i| Workload.outer(i) }
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

session&.stop

puts "BULLDOGGER_BENCH_ELAPSED: #{elapsed}"
