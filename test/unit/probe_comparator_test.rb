# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../fixtures/probe/target_app"

class ProbeComparatorTest < Minitest::Test
  def test_two_probes_of_unchanged_code_are_identical
    path_a = probe_snapshot_three_times
    path_b = probe_snapshot_three_times

    result = Bulldogger.probe_compare(path_a, path_b)

    assert_equal true, result["identical"],
                 "expected no differences, got: #{result['differences'].inspect}"
    assert_empty result["differences"]
  end

  # Proves the address-normalization this needs: #snapshot returns
  # self, and two separate Invoice instances (one per probe run) have
  # different #inspect object addresses -- a comparator that did not
  # normalize 0x... out of samples would report a difference here
  # even though nothing about the method's own behavior changed.
  def test_identical_comparison_survives_object_addresses_in_samples
    path_a = probe_snapshot_three_times
    path_b = probe_snapshot_three_times
    data_a = JSON.parse(File.read(path_a))
    data_b = JSON.parse(File.read(path_b))
    sample_a = data_a.dig("methods", "Billing::Invoice#snapshot", "returns", "samples", 0, "value")
    sample_b = data_b.dig("methods", "Billing::Invoice#snapshot", "returns", "samples", 0, "value")
    refute_equal sample_a, sample_b, "the fixture must actually produce different raw addresses"

    result = Bulldogger.probe_compare(path_a, path_b)

    assert_equal true, result["identical"]
  end

  def test_a_return_type_change_is_detected_and_named
    path_a = probe_amount { |invoice| invoice.amount(3) }
    path_b = probe_amount { |invoice| invoice.amount("3") } # returns a String, not an Integer

    result = Bulldogger.probe_compare(path_a, path_b)

    refute result["identical"]
    assert(result["differences"].any? { |d| d.include?("returns.classes") },
           "differences: #{result['differences'].inspect}")
  end

  def test_a_newly_appearing_nil_is_detected_and_named
    path_a = probe_amount { |invoice| invoice.amount(3, discount: 1) }
    path_b = probe_amount { |invoice| invoice.amount(3) } # discount now nil

    result = Bulldogger.probe_compare(path_a, path_b)

    refute result["identical"]
    assert(result["differences"].any? { |d| d.include?("param discount.nil_count") },
           "differences: #{result['differences'].inspect}")
  end

  def test_a_call_count_change_is_detected_and_named
    path_a = probe_amount { |invoice| invoice.amount(1) }
    path_b = probe_amount { |invoice| 2.times { invoice.amount(1) } }

    result = Bulldogger.probe_compare(path_a, path_b)

    refute result["identical"]
    assert(result["differences"].any? { |d| d.include?(".calls changed") },
           "differences: #{result['differences'].inspect}")
  end

  private

  # Routed through one shared call site (this method), on purpose: the
  # two probe runs must be indistinguishable in *everything except*
  # object identity, or a caller-set difference (a real, correctly
  # detected difference) would be mistaken for the normalization bug
  # this test exists to catch.
  def probe_snapshot_three_times
    invoice = Billing::Invoice.new
    Bulldogger.probe("Billing::Invoice#snapshot") { 3.times { invoice.snapshot } }
  end

  def probe_amount
    invoice = Billing::Invoice.new
    Bulldogger.probe("Billing::Invoice#amount") { yield invoice }
  end
end
