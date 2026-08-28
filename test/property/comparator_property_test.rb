# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../fixtures/probe/target_app"

# Generalizes probe_comparator_test.rb's hand-picked cases: for an
# arbitrary generated call workload, probing the same workload twice
# must report identical:true, and appending one more generated call
# must always be detected as a difference.
#
# Every workload here probes Billing::Invoice#snapshot at least once,
# not just #amount: #amount only ever returns an Integer, so a
# workload built from it alone can never put a raw object address
# (the thing Comparator's normalization exists to see through) into a
# sample, and "identical: true" would hold even with normalization
# disabled -- exactly the gap this file's own falsification run
# caught (see the task report). #snapshot returns self, whose default
# #inspect embeds a fresh address on every Invoice instance, so its
# presence is what makes normalization load-bearing for this test.
class ComparatorPropertyTest < Minitest::Test
  TARGETS = ["Billing::Invoice#amount", "Billing::Invoice#snapshot"].freeze

  def test_two_probes_of_the_same_generated_workload_are_always_identical
    Hegel.test(test_cases: 30) do |tc|
      workload = tc.draw(workload_generator, label: "workload")

      path_a = probe_workload(workload)
      path_b = probe_workload(workload)
      result = Bulldogger.probe_compare(path_a, path_b)

      assert_equal true, result["identical"], "differences: #{result['differences'].inspect}"
      assert_empty result["differences"]
    end
  end

  def test_appending_one_generated_call_is_always_detected
    Hegel.test(test_cases: 30) do |tc|
      amount_calls, snapshot_count = tc.draw(workload_generator, label: "workload")
      extra_call = tc.draw(call_spec_generator, label: "extra_call")

      path_a = probe_workload([amount_calls, snapshot_count])
      path_b = probe_workload([amount_calls + [extra_call], snapshot_count])
      result = Bulldogger.probe_compare(path_a, path_b)

      refute result["identical"]
      assert(result["differences"].any? { |d| d.include?(".calls changed") },
             "differences: #{result['differences'].inspect}")
    end
  end

  private

  def call_spec_generator
    tuples(integers(min_value: 1, max_value: 50), optional(integers(min_value: 0, max_value: 20)))
  end

  # [amount_calls, snapshot_count]: snapshot_count's minimum of 1 is
  # deliberate (see the class comment) -- every generated workload
  # must call #snapshot at least once, or the property never actually
  # exercises address normalization.
  def workload_generator
    tuples(
      arrays(call_spec_generator, min_size: 0, max_size: 5),
      integers(min_value: 1, max_value: 5)
    )
  end

  # One shared call site for every probe run in this file: comparing
  # two runs whose calls came from different lines would report a
  # real, correctly-detected callers difference that has nothing to
  # do with the property under test (probe_comparator_test.rb notes
  # the same reasoning for its own probe_amount helper).
  def probe_workload(workload)
    amount_calls, snapshot_count = workload
    invoice = Billing::Invoice.new
    Bulldogger.probe(*TARGETS) do
      amount_calls.each { |mult, discount| invoice.amount(mult, discount: discount) }
      snapshot_count.times { invoice.snapshot }
    end
  end
end
