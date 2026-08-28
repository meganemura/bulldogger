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

  # The kill switch's own overhead: Bulldogger.start still runs (a
  # real app calls it unconditionally), but config.enabled is false
  # first, so it should cost the same as never having required the
  # gem ("off"), not the same as actively capturing ("on"). rescue_heavy
  # is the mode that would show it, since raise_free never raises and
  # red's cost is dominated by disk writes neither condition performs.
  disabled_elapsed = Array.new(runs_per_condition) { bench_once.call("rescue_heavy", "disabled") }
  results[["rescue_heavy", "disabled"]] = median.call(disabled_elapsed)
  puts "  rescue_heavy disabled: #{disabled_elapsed.map { |e| format('%.4f', e) }.join(', ')} " \
       "-> median #{format('%.4f', results[['rescue_heavy', 'disabled']])}s"

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
  without = results[["rescue_heavy", "off"]]
  with = results[["rescue_heavy", "disabled"]]
  puts format("| %s | %.4f | %.4f | %.2fx | %s |", "rescue_heavy (switch disabled)", without, with,
              with / without, "Bulldogger.start runs but never subscribes")

  # Breaks the rescue_heavy "on" number above into what each step of
  # the pipeline costs: subscribing to :raise, calling
  # DEBUGGER__.capture_frames, and this library's own serialization +
  # redaction + Pending ring. See
  # test/fixtures/overhead/frame_capture_breakdown.rb.
  puts
  puts "Running the frame-capture breakdown #{runs_per_condition}x per tier (median reported)..."
  breakdown_script = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/overhead/frame_capture_breakdown.rb")
  breakdown_iterations = 10_000

  breakdown_once = lambda do |tier|
    stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", breakdown_script, tier,
                                             chdir: BulldoggerAcceptanceHelper::ROOT)
    raise "breakdown #{tier} failed: #{stderr}" unless status.success?

    stdout[/BULLDOGGER_BENCH_ELAPSED: ([\d.eE+-]+)/, 1].to_f
  end

  breakdown_results = {}
  %w[bare_tracepoint capture_frames full].each do |tier|
    elapsed = Array.new(runs_per_condition) { breakdown_once.call(tier) }
    breakdown_results[tier] = median.call(elapsed)
    puts "  #{tier}: #{elapsed.map { |e| format('%.4f', e) }.join(', ')} -> median #{format('%.4f', breakdown_results[tier])}s"
  end

  puts
  puts "| tier | total (s) | µs/exception over baseline | incremental µs/exception |"
  puts "|---|---|---|---|"
  baseline = results[["rescue_heavy", "off"]]
  previous = baseline
  %w[bare_tracepoint capture_frames full].each do |tier|
    total = breakdown_results[tier]
    over_baseline = ((total - baseline) / breakdown_iterations) * 1_000_000
    incremental = ((total - previous) / breakdown_iterations) * 1_000_000
    puts format("| %s | %.4f | %.3f | %.3f |", tier, total, over_baseline, incremental)
    previous = total
  end
end
