# frozen_string_literal: true

# Measures the proportionality law contract-verbs.md's "probe の性能
# 条件" now stands on: probe's cost scales with calls to the targeted
# method M, record's with total calls N. Not part of `rake` or
# `rake acceptance` -- like probe_overhead/record_overhead, several
# runs per condition are too slow for every `bundle exec rake`.
#
# This does not assert pass/fail. It prints what the fixture and the
# real artifacts (probe's evidence JSON, record's JSONL) measured; the
# report built from this task's output states in prose whether the
# law showed up, per the task's own instruction not to fake it by
# choosing a flattering workload.
desc "Measure the probe/record proportionality law (see test/fixtures/proportionality/bench.rb); prints tables, does not assert"
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

  # Runs bench.rb once, parses its printed fields, and cross-checks
  # the fixture's own counters against the real artifact bulldogger
  # wrote (probe's evidence JSON "calls", record's JSONL "call" line
  # count) -- not each other's estimate, the actual mechanism output.
  # A mismatch here means the mechanism is not behaving the way this
  # task assumes, which is the documented reason to stop rather than
  # report a number built on a wrong assumption.
  bench_once = lambda do |mode, target_calls, other_calls|
    stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", bench_script, mode,
                                             target_calls.to_s, other_calls.to_s,
                                             chdir: BulldoggerAcceptanceHelper::ROOT)
    raise "bench #{mode} #{target_calls} #{other_calls} failed: #{stderr}" unless status.success?

    fields = {
      elapsed: stdout[/BULLDOGGER_BENCH_ELAPSED: ([\d.eE+-]+)/, 1]&.to_f,
      fixture_m: stdout[/BULLDOGGER_BENCH_FIXTURE_M: (\d+)/, 1]&.to_i,
      fixture_n: stdout[/BULLDOGGER_BENCH_FIXTURE_N: (\d+)/, 1]&.to_i,
      artifact_m: stdout[/BULLDOGGER_BENCH_ARTIFACT_M: (\d+)/, 1]&.to_i,
      artifact_n: stdout[/BULLDOGGER_BENCH_ARTIFACT_N: (\d+)/, 1]&.to_i
    }

    if mode == "probe" && fields[:artifact_m] != target_calls
      raise "proportionality: probe evidence recorded #{fields[:artifact_m]} calls to the " \
            "target, expected #{target_calls} (fixture-counted: #{fields[:fixture_m]}) -- " \
            "the mechanism is not behaving as understood, stopping rather than reporting a " \
            "number built on a wrong assumption."
    end
    if mode == "record" && fields[:artifact_n] != fields[:fixture_n]
      raise "proportionality: record's JSONL recorded #{fields[:artifact_n]} call events, " \
            "the fixture's own counters say #{fields[:fixture_n]} -- the mechanism is not " \
            "behaving as understood, stopping rather than reporting a number built on a " \
            "wrong assumption."
    end

    fields
  end

  # Runs all three modes (baseline/probe/record) runs_per_condition
  # times each for one (target_calls, other_calls) config, returns a
  # Hash of median elapsed seconds plus the config's M/N (read from
  # the fixture's own counters, which the checks above already proved
  # equal to what the real artifacts recorded).
  measure_config = lambda do |target_calls, other_calls|
    result = { target_calls: target_calls, other_calls: other_calls }
    %w[baseline probe record].each do |mode|
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

  # Prints one direction's table: M, N, the three raw timings, each
  # non-baseline timing's delta over baseline (the cost attributable
  # to bulldogger, not to the workload growing on its own), and that
  # delta normalized per call to the count each verb's cost is claimed
  # to scale with (M for probe, N for record). Flat vs. growing is
  # judged on the last two columns, not on raw seconds -- the raw
  # workload itself grows across a direction's rows, so raw elapsed
  # alone would rise even if bulldogger's own added cost were exactly
  # flat.
  print_table = lambda do |title, rows|
    puts
    puts "### #{title}"
    puts
    puts "| M | N | baseline (s) | probe (s) | record (s) | probe - baseline (s) | " \
         "record - baseline (s) | probe overhead (ns/M) | record overhead (ns/N) |"
    puts "|---|---|---|---|---|---|---|---|---|"
    rows.each do |r|
      probe_delta = r[:probe_s] - r[:baseline_s]
      record_delta = r[:record_s] - r[:baseline_s]
      probe_ns_per_m = (probe_delta / r[:m]) * 1_000_000_000
      record_ns_per_n = (record_delta / r[:n]) * 1_000_000_000
      puts format("| %d | %d | %.4f | %.4f | %.4f | %.4f | %.4f | %.1f | %.1f |",
                   r[:m], r[:n], r[:baseline_s], r[:probe_s], r[:record_s],
                   probe_delta, record_delta, probe_ns_per_m, record_ns_per_n)
    end
  end

  # Direction A: M fixed, N (total calls: target + other) rises across
  # 3 steps by growing only the non-target call count.
  puts "Direction A: M fixed at 20,000, other-method calls rising (2-3 steps)..."
  direction_a_target = 20_000
  direction_a = [20_000, 60_000, 140_000].map { |other| measure_config.call(direction_a_target, other) }

  # Direction B: N (total calls) fixed, M rising as a larger share of
  # it. Total fixed at 160,000 -- the same total Direction A's largest
  # row reaches, so both directions' heaviest record row costs about
  # the same and neither table's grid was picked after seeing numbers.
  puts
  puts "Direction B: total calls fixed at 160,000, M rising as a share of it (2-3 steps)..."
  direction_b_total = 160_000
  direction_b = [16_000, 80_000, 144_000].map { |m| measure_config.call(m, direction_b_total - m) }

  print_table.call("Direction A -- M fixed, N rising", direction_a)
  print_table.call("Direction B -- N fixed, M rising", direction_b)

  # Publication point: reuse Direction B's middle row (M is half of N)
  # rather than running a new config -- contract-verbs.md's own text
  # says the same app-shaped fixture is fine for this, and reusing an
  # already-measured row rules out picking a fresh config because its
  # ratio looks better.
  pub = direction_b[1]
  pub_probe_ratio = pub[:probe_s] / pub[:baseline_s]
  pub_record_ratio = pub[:record_s] / pub[:baseline_s]
  puts
  puts "### Publication point (reused from Direction B's middle row, not a fresh fixture)"
  puts
  puts "| M | N | M/N | baseline (s) | probe (s) | probe ratio | record (s) | record ratio |"
  puts "|---|---|---|---|---|---|---|---|"
  puts format("| %d | %d | %.2f | %.4f | %.4f | %.2fx | %.4f | %.2fx |",
               pub[:m], pub[:n], pub[:m].to_f / pub[:n], pub[:baseline_s], pub[:probe_s],
               pub_probe_ratio, pub[:record_s], pub_record_ratio)
  puts
  puts "In this app, probe (M=#{pub[:m]}) is #{format('%.2f', pub_probe_ratio)}x baseline and " \
       "record (N=#{pub[:n]}) is #{format('%.2f', pub_record_ratio)}x baseline, at M/N = " \
       "#{format('%.2f', pub[:m].to_f / pub[:n])}. probe scales with M, record with N -- a " \
       "different M/N in another app reads differently, this ratio is not \"probe is one " \
       "order of magnitude cheaper.\""

  puts
  puts "### Absolute values (this harness, plus the canonical published figures)"
  puts
  puts "| source | measure | value |"
  puts "|---|---|---|"
  all_rows = direction_a + direction_b
  probe_ns_per_m_values = all_rows.map { |r| ((r[:probe_s] - r[:baseline_s]) / r[:m]) * 1_000_000_000 }
  record_ns_per_n_values = all_rows.map { |r| ((r[:record_s] - r[:baseline_s]) / r[:n]) * 1_000_000_000 }
  puts format("| this harness | probe overhead, ns/M (median across all 6 rows) | %.1f |",
              median.call(probe_ns_per_m_values))
  puts format("| this harness | record overhead, ns/N (median across all 6 rows) | %.1f |",
              median.call(record_ns_per_n_values))
  puts "| task K (g-probe.md/k-probe-cost.md, post-optimization) | probe ratio, trivial workload | 41.18-46.03x |"
  puts "| task K | probe ratio, realistic workload | 11.17-11.19x |"
  puts "| task K | probe overhead, ns/call, trivial | 1118.2-1158.6 |"
  puts "| task K | probe overhead, ns/call, realistic | 1361.6-1366.9 |"
  puts "| task H (h-record.md) | record ratio, capture only | 40.94x |"
  puts "| task H | record ratio, write included | 58.34x |"

  puts
  puts "probe is an explicit verb run once around a set of tests, not something a whole suite " \
       "pays on every run -- see tasks/probe.rake and tasks/record.rake for that framing on " \
       "each verb's own absolute cost."
end
