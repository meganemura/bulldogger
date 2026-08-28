# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../fixtures/probe/target_app"

# MethodStats aggregates without a per-call Mutex: each thread writes
# into its own thread-local bucket, merged once at finish. This file
# is the proof that the merge is exact -- calling the same target the
# same number of times from several threads must report identical
# totals to calling it that many times from one thread, or the
# per-call Mutex removal silently dropped or double-counted calls.
class ProbeConcurrencyTest < Minitest::Test
  THREAD_COUNT = 4
  CALLS_PER_THREAD = 50
  TOTAL_CALLS = THREAD_COUNT * CALLS_PER_THREAD

  def test_calls_from_several_threads_aggregate_exactly_like_one_thread
    invoice = Billing::Invoice.new

    stats = probe_and_read("Billing::Invoice#amount") do
      threads = Array.new(THREAD_COUNT) do
        Thread.new { CALLS_PER_THREAD.times { |i| invoice.amount(i) } }
      end
      threads.each(&:join)
    end

    method_stats = stats["Billing::Invoice#amount"]
    assert_equal TOTAL_CALLS, method_stats["calls"]
    assert_equal TOTAL_CALLS, method_stats["returns"]["classes"]["Integer"]
    assert_equal 0, method_stats["returns"]["nil_count"]
    assert_equal TOTAL_CALLS, method_stats["params"]["mult"]["classes"]["Integer"]
  end

  # Each thread's own Bucket caps its samples at max_samples
  # independently (no cross-thread coordination happens per call, by
  # design). Bucket#merge! must re-cap at max_samples when folding
  # those thread-local buckets together, or a target hit by several
  # threads would publish up to thread_count * max_samples samples --
  # quietly widening the documented limit.
  def test_merged_samples_stay_capped_at_max_samples_regardless_of_thread_count
    invoice = Billing::Invoice.new

    stats = probe_and_read("Billing::Invoice#amount") do
      threads = Array.new(THREAD_COUNT) do
        Thread.new { CALLS_PER_THREAD.times { |i| invoice.amount(i) } }
      end
      threads.each(&:join)
    end

    returns = stats["Billing::Invoice#amount"]["returns"]
    max_samples = Bulldogger.config.max_samples
    assert_equal max_samples, returns["samples"].size
    assert_equal TOTAL_CALLS - max_samples, returns["samples_omitted"]
  end

  private

  def probe_and_read(*targets, &block)
    path = Bulldogger.probe(*targets, &block)
    JSON.parse(File.read(path))["methods"]
  end
end
