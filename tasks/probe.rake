# frozen_string_literal: true

# Measures probe's absolute per-call overhead. Not part of
# `rake acceptance` or the default task, matching tasks/acceptance.rake's
# own :overhead task: several runs per condition, reporting a median,
# is too slow for every `bundle exec rake`.
desc "Measure Bulldogger's probe overhead (see test/fixtures/probe/bench.rb); prints a table, does not assert"
task :probe_overhead do
  require "open3"
  require_relative "../test/acceptance/acceptance_helper"

  runs_per_condition = 3
  bench_script = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/probe/bench.rb")
  iterations = { "trivial" => 500_000, "realistic" => 200_000 }

  bench_once = lambda do |workload, condition|
    stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", bench_script, workload, condition,
                                             chdir: BulldoggerAcceptanceHelper::ROOT)
    raise "bench #{workload} #{condition} failed: #{stderr}" unless status.success?

    stdout[/BULLDOGGER_BENCH_ELAPSED: ([\d.eE+-]+)/, 1].to_f
  end

  median = lambda do |values|
    sorted = values.sort
    mid = sorted.length / 2
    sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  puts "Running each condition #{runs_per_condition}x (median reported)..."
  results = {}
  %w[trivial realistic].each do |workload|
    %w[off bare on].each do |condition|
      elapsed = Array.new(runs_per_condition) { bench_once.call(workload, condition) }
      results[[workload, condition]] = median.call(elapsed)
      puts "  #{workload} #{condition}: #{elapsed.map { |e| format('%.4f', e) }.join(', ')} " \
           "-> median #{format('%.4f', results[[workload, condition]])}s"
    end
  end

  puts
  puts "| workload (iterations) | without (s) | bare-TP (s) | probe on (s) | bare ratio | probe ratio | ns/call added by bare TP | ns/call added by probe |"
  puts "|---|---|---|---|---|---|---|---|"
  %w[trivial realistic].each do |workload|
    without = results[[workload, "off"]]
    bare = results[[workload, "bare"]]
    with = results[[workload, "on"]]
    n = iterations.fetch(workload)
    puts format("| %s (%d) | %.4f | %.4f | %.4f | %.2fx | %.2fx | %.1f | %.1f |",
                 workload, n, without, bare, with, bare / without, with / without,
                 ((bare - without) / n) * 1_000_000_000, ((with - without) / n) * 1_000_000_000)
  end

  puts
  puts "Absolute cost, not a ratio, is what this reports: probe is an explicit verb run once " \
       "around a test, not something a whole suite pays on every run. Most of this is per-call " \
       "aggregation the design requires on every call (classes/nil_count tally, caller_locations, " \
       "the raise/rescue checkpoint) -- see the report for what was reducible and what was not."
end
