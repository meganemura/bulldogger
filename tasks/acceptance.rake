# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:acceptance) do |t|
  t.libs << "test"
  t.test_files = FileList["test/acceptance/**/*_test.rb"]
  t.verbose = true
end

# Not part of `rake acceptance` or the default task: this measures the
# AGENTS.md overhead claims (ratio with/without Bulldogger active,
# microseconds per exception) rather than asserting pass/fail, and
# each condition needs several runs to report a stable median -- too
# slow to belong in every `bundle exec rake`.
desc "Measure Bulldogger's overhead (see test/fixtures/overhead/bench.rb); prints a table, does not assert"
task :overhead do
  require "open3"
  require_relative "../test/acceptance/acceptance_helper"

  runs_per_condition = 3
  bench_script = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/overhead/bench.rb")
  iterations = { "raise_free" => 2_000_000, "rescue_heavy" => 10_000, "red" => 200 }

  bench_once = lambda do |mode, toggle|
    stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", bench_script, mode, toggle,
                                             chdir: BulldoggerAcceptanceHelper::ROOT)
    raise "bench #{mode} #{toggle} failed: #{stderr}" unless status.success?

    stdout[/BULLDOGGER_BENCH_ELAPSED: ([\d.eE+-]+)/, 1].to_f
  end

  median = lambda do |values|
    sorted = values.sort
    mid = sorted.length / 2
    sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  puts "Running each condition #{runs_per_condition}x (median reported)..."
  results = {}
  %w[raise_free rescue_heavy red].each do |mode|
    %w[off on].each do |toggle|
      elapsed = Array.new(runs_per_condition) { bench_once.call(mode, toggle) }
      results[[mode, toggle]] = median.call(elapsed)
      puts "  #{mode} #{toggle}: #{elapsed.map { |e| format('%.4f', e) }.join(', ')} -> median #{format('%.4f', results[[mode, toggle]])}s"
    end
  end

  puts
  puts "| condition | without (s) | with (s) | ratio | notes |"
  puts "|---|---|---|---|---|"
  %w[raise_free rescue_heavy red].each do |mode|
    without = results[[mode, "off"]]
    with = results[[mode, "on"]]
    ratio = with / without
    note = mode == "rescue_heavy" ? "#{format('%.3f', ((with - without) / iterations.fetch(mode)) * 1_000_000)} µs/exception" : ""
    puts format("| %s | %.4f | %.4f | %.2fx | %s |", mode, without, with, ratio, note)
  end
end
