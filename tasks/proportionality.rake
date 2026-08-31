# frozen_string_literal: true

# Measures the proportionality law probe's performance rests on: probe's
# cost scales with calls to its targeted method (M), not with the total
# call count across the workload (N). Not part of `rake` or
# `rake acceptance` -- like probe_overhead, several runs per condition
# are too slow for every `bundle exec rake`.
#
# This does not assert pass/fail. It prints what the fixture and the
# real artifact (probe's evidence JSON) measured; the report built from
# this task's output states in prose whether the law showed up, per the
# task's own instruction not to fake it by choosing a flattering
# workload.
desc "Measure the probe proportionality law (see test/fixtures/proportionality/bench.rb); prints tables, does not assert"
task :proportionality do
  require "open3"
  require_relative "../test/acceptance/acceptance_helper"

  bench_script = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/proportionality/bench.rb")
  runs_per_condition = 3

  median = lambda do |values|
    sorted = values.sort
    mid = sorted.length / 2
    sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  # Runs bench.rb once, parses its printed fields, and cross-checks the
  # fixture's own counters against the real artifact bulldogger wrote
  # (probe's evidence JSON "calls" count) -- not an estimate, the
  # actual mechanism output. A mismatch here means the mechanism is not
  # behaving the way this task assumes, which is the documented reason
  # to stop rather than report a number built on a wrong assumption.
  bench_once = lambda do |mode, target_calls, other_calls|
    stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", bench_script, mode,
                                             target_calls.to_s, other_calls.to_s,
                                             chdir: BulldoggerAcceptanceHelper::ROOT)
    raise "bench #{mode} #{target_calls} #{other_calls} failed: #{stderr}" unless status.success?

    fields = {
      elapsed: stdout[/BULLDOGGER_BENCH_ELAPSED: ([\d.eE+-]+)/, 1]&.to_f,
      fixture_m: stdout[/BULLDOGGER_BENCH_FIXTURE_M: (\d+)/, 1]&.to_i,
      fixture_n: stdout[/BULLDOGGER_BENCH_FIXTURE_N: (\d+)/, 1]&.to_i,
      artifact_m: stdout[/BULLDOGGER_BENCH_ARTIFACT_M: (\d+)/, 1]&.to_i
    }

    if mode == "probe" && fields[:artifact_m] != target_calls
      raise "proportionality: probe evidence recorded #{fields[:artifact_m]} calls to the " \
            "target, expected #{target_calls} (fixture-counted: #{fields[:fixture_m]}) -- " \
            "the mechanism is not behaving as understood, stopping rather than reporting a " \
            "number built on a wrong assumption."
    end

    fields
  end

  # Runs both modes (baseline/probe) runs_per_condition times each for
  # one (target_calls, other_calls) config, returns a Hash of median
  # elapsed seconds plus the config's M/N (read from the fixture's own
  # counters, which the check above already proved equal to what the
  # real artifact recorded).
  measure_config = lambda do |target_calls, other_calls|
    result = { target_calls: target_calls, other_calls: other_calls }
    %w[baseline probe].each do |mode|
      runs = Array.new(runs_per_condition) { bench_once.call(mode, target_calls, other_calls) }
      result[:"#{mode}_s"] = median.call(runs.map { |r| r[:elapsed] })
      result[:m] ||= runs.first[:fixture_m]
      result[:n] ||= runs.first[:fixture_n]
      puts "  #{mode} target=#{target_calls} other=#{other_calls}: " \
           "#{runs.map { |r| format('%.4f', r[:elapsed]) }.join(', ')} -> " \
           "median #{format('%.4f', result[:"#{mode}_s"])}s"
    end
    result
  end

  # Prints one direction's table: M, N, the two raw timings, probe's
  # delta over baseline (the cost attributable to bulldogger, not to
  # the workload growing on its own), and that delta normalized per
  # call to M, the count probe's cost is claimed to scale with. Flat
  # vs. growing is judged on the last two columns, not on raw seconds
  # -- the raw workload itself grows across a direction's rows, so raw
  # elapsed alone would rise even if bulldogger's own added cost were
  # exactly flat.
  print_table = lambda do |title, rows|
    puts
    puts "### #{title}"
    puts
    puts "| M | N | baseline (s) | probe (s) | probe - baseline (s) | probe overhead (ns/M) |"
    puts "|---|---|---|---|---|---|"
    rows.each do |r|
      probe_delta = r[:probe_s] - r[:baseline_s]
      probe_ns_per_m = (probe_delta / r[:m]) * 1_000_000_000
      puts format("| %d | %d | %.4f | %.4f | %.4f | %.1f |",
                   r[:m], r[:n], r[:baseline_s], r[:probe_s], probe_delta, probe_ns_per_m)
    end
  end

  # Direction A: M fixed, N (total calls: target + other) rises across
  # 3 steps by growing only the non-target call count.
  puts "Direction A: M fixed at 20,000, other-method calls rising (2-3 steps)..."
  direction_a_target = 20_000
  direction_a = [20_000, 60_000, 140_000].map { |other| measure_config.call(direction_a_target, other) }

  # Direction B: N (total calls) fixed, M rising as a larger share of
  # it. Total fixed at 160,000 -- the same total Direction A's largest
  # row reaches, so both directions' heaviest row costs about the same
  # and neither table's grid was picked after seeing numbers.
  puts
  puts "Direction B: total calls fixed at 160,000, M rising as a share of it (2-3 steps)..."
  direction_b_total = 160_000
  direction_b = [16_000, 80_000, 144_000].map { |m| measure_config.call(m, direction_b_total - m) }

  print_table.call("Direction A -- M fixed, N rising", direction_a)
  print_table.call("Direction B -- N fixed, M rising", direction_b)

  # Publication point: reuse Direction B's middle row (M is half of N)
  # rather than running a new config -- the law holds for any M/N
  # split on the same app-shaped fixture, and reusing an
  # already-measured row rules out picking a fresh config because its
  # ratio looks better.
  pub = direction_b[1]
  pub_probe_ratio = pub[:probe_s] / pub[:baseline_s]
  puts
  puts "### Publication point (reused from Direction B's middle row, not a fresh fixture)"
  puts
  puts "| M | N | M/N | baseline (s) | probe (s) | probe ratio |"
  puts "|---|---|---|---|---|---|"
  puts format("| %d | %d | %.2f | %.4f | %.4f | %.2fx |",
               pub[:m], pub[:n], pub[:m].to_f / pub[:n], pub[:baseline_s], pub[:probe_s], pub_probe_ratio)
  puts
  puts "In this app, probe (M=#{pub[:m]}) is #{format('%.2f', pub_probe_ratio)}x baseline at " \
       "M/N = #{format('%.2f', pub[:m].to_f / pub[:n])}. probe scales with M, not N -- a " \
       "different M/N in another app reads differently, this ratio is not \"probe costs one " \
       "fixed multiple.\""

  puts
  puts "### Absolute values (this harness, plus an earlier proportionality measurement)"
  puts
  puts "| source | measure | value |"
  puts "|---|---|---|"
  all_rows = direction_a + direction_b
  probe_ns_per_m_values = all_rows.map { |r| ((r[:probe_s] - r[:baseline_s]) / r[:m]) * 1_000_000_000 }
  puts format("| this harness | probe overhead, ns/M (median across all 6 rows) | %.1f |",
              median.call(probe_ns_per_m_values))
  puts "| docs/design-decisions.md, \"Measure the shipped event work\" | probe cost per targeted call | 1353.3 ns |"
  puts "| docs/design-decisions.md, \"Update the explicit verb measurements in version 0.2\" | probe ratio at M/N = 0.25 | 9.07x |"

  puts
  puts "probe is an explicit verb run once around a set of tests, not something a whole suite " \
       "pays on every run -- see tasks/probe.rake for that framing on its own absolute cost."
end
