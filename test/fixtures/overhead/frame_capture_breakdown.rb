# frozen_string_literal: true

# Breaks the rescue_heavy overhead measured by bench.rb's "on"
# condition into the three things a raise pays for, in order:
# subscribing to :raise at all, calling DEBUGGER__.capture_frames,
# and this library's own serialization + redaction + Pending ring.
# Each tier is its own process with its own TracePoint, so an
# earlier tier's hook is never still enabled while a later tier
# runs.
#
# ARGV: tier ("bare_tracepoint" | "capture_frames" | "full")
# Prints one line: "BULLDOGGER_BENCH_ELAPSED: <seconds>"

require "tmpdir"

tier = ARGV[0]
ITERATIONS = 10_000

case tier
when "bare_tracepoint"
  # Tier 1: the cost of :raise firing on every raise, before this
  # library does anything with the event.
  TracePoint.new(:raise) { |_tp| nil }.enable
when "capture_frames"
  # Tier 2: tier 1 plus DEBUGGER__.capture_frames itself, with
  # nothing done to what it returns. FrameSource#capture (the real
  # call site, lib/bulldogger/frame_source.rb) always serializes in
  # the same pass, so there is no production method to call here for
  # "capture only" -- this reproduces its call shape by hand instead,
  # using the same skip_path_prefix computation so the frame count
  # capture_frames has to walk is the one this library actually asks
  # for, not a wider or narrower stand-in.
  require "bulldogger"
  require "debug/frame_info"
  skip_path_prefix = Bulldogger::FrameSource.default_skip_path_prefix
  TracePoint.new(:raise) { |_tp| DEBUGGER__.capture_frames(skip_path_prefix) }.enable
when "full"
  # Tier 3: today's actual pipeline -- capture, serialize, redact,
  # store in the Pending ring. The same code path bench.rb's
  # "rescue_heavy on" condition measures; it is reproduced here too
  # so its number sits in the same table as tiers 1 and 2, rather
  # than requiring a reader to line up two separate outputs by hand.
  require "bulldogger"
  Bulldogger.config.output_dir = Dir.mktmpdir("bulldogger-bench-")
  Bulldogger.start
else
  raise ArgumentError, "unknown tier: #{tier.inspect}"
end

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ITERATIONS.times do |i|
  raise "boom #{i}"
rescue RuntimeError
  nil
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

Bulldogger.finish if tier == "full"

puts "BULLDOGGER_BENCH_ELAPSED: #{elapsed}"
