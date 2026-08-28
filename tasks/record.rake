# frozen_string_literal: true

# Not part of `rake` or `rake acceptance`: this measures Record's
# overhead claim rather than asserting pass/fail, and each tier needs
# several runs to report a stable median -- too slow to belong in
# every `bundle exec rake`. Mirrors tasks/acceptance.rake's `overhead`
# task, adapted for Record's three-tier split instead of Capture's
# on/off/disabled split.
desc "Measure Bulldogger::Record's overhead (see test/fixtures/record/bench.rb); prints a table, does not assert"
task :record_overhead do
  require "open3"
  require_relative "../test/acceptance/acceptance_helper"

  runs_per_tier = 3
  bench_script = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/record/bench.rb")

  bench_once = lambda do |tier|
    stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", bench_script, tier,
                                             chdir: BulldoggerAcceptanceHelper::ROOT)
    raise "bench #{tier} failed: #{stderr}" unless status.success?

    stdout[/BULLDOGGER_BENCH_ELAPSED: ([\d.eE+-]+)/, 1].to_f
  end

  median = lambda do |values|
    sorted = values.sort
    mid = sorted.length / 2
    sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  puts "Running each tier #{runs_per_tier}x (median reported)..."
  results = {}
  %w[baseline capture_only full].each do |tier|
    elapsed = Array.new(runs_per_tier) { bench_once.call(tier) }
    results[tier] = median.call(elapsed)
    puts "  #{tier}: #{elapsed.map { |e| format('%.4f', e) }.join(', ')} -> median #{format('%.4f', results[tier])}s"
  end

  puts
  puts "| tier | seconds | ratio vs baseline | notes |"
  puts "|---|---|---|---|"
  baseline = results["baseline"]
  notes = {
    "baseline" => "no Bulldogger::Record involvement",
    "capture_only" => "TracePoint dispatch + Formatter/Redactor, no JSONL write (value capture only)",
    "full" => "the shipped Record.run path, including the JSONL write (write included)"
  }
  %w[baseline capture_only full].each do |tier|
    ratio = results[tier] / baseline
    puts format("| %s | %.4f | %.2fx | %s |", tier, results[tier], ratio, notes[tier])
  end
end
