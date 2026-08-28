# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../fixtures/probe/target_app"

class ProbeCaptureTest < Minitest::Test
  Invoice = Billing::Invoice

  def test_instance_and_singleton_methods_can_both_be_targets
    invoice = Invoice.new
    stats = probe_and_read("Billing::Invoice#amount", "Order.total") do
      invoice.amount(2)
      Order.total(3)
    end

    assert_equal 1, stats["Billing::Invoice#amount"]["calls"]
    assert_equal 1, stats["Order.total"]["calls"]
  end

  def test_target_filtering_is_strict
    invoice = Invoice.new
    stats = probe_and_read("Billing::Invoice#amount") do
      3.times { invoice.amount(1) }
      5.times { Untouched.ping }
    end

    assert_equal ["Billing::Invoice#amount"], stats.keys
    assert_equal 3, stats["Billing::Invoice#amount"]["calls"]
  end

  def test_actual_arguments_are_recorded_by_name_including_a_defaulted_keyword
    invoice = Invoice.new
    stats = probe_and_read("Billing::Invoice#amount") do
      invoice.amount(4) # discount omitted -- must still show up as nil
    end

    params = stats["Billing::Invoice#amount"]["params"]
    assert_equal({ "value" => "4" }, params["mult"]["samples"].first)
    assert_equal({ "value" => "nil" }, params["discount"]["samples"].first)
    assert_equal 1, params["discount"]["nil_count"]
  end

  def test_return_value_class_and_nil_count_are_recorded
    invoice = Invoice.new
    stats = probe_and_read("Billing::Invoice#amount") do
      invoice.amount(3)
      invoice.amount(5, discount: 50)
    end

    returns = stats["Billing::Invoice#amount"]["returns"]
    assert_equal({ "Integer" => 2 }, returns["classes"])
    assert_equal 0, returns["nil_count"]
  end

  def test_raise_exit_is_counted_separately_from_a_nil_return
    invoice = Invoice.new
    stats = probe_and_read("Billing::Invoice#blows_up") do
      begin
        invoice.blows_up
      rescue ArgumentError
        nil
      end
    end

    method_stats = stats["Billing::Invoice#blows_up"]
    assert_equal 1, method_stats["calls"]
    assert_equal 1, method_stats["raised_exits"]
    assert_equal({ "ArgumentError" => 1 }, method_stats["raised"])
    assert_equal 0, method_stats["returns"]["classes"].values.sum
    assert_equal 0, method_stats["returns"]["nil_count"]
  end

  def test_a_raise_recovered_inside_the_target_counts_as_a_normal_return
    invoice = Invoice.new
    stats = probe_and_read("Billing::Invoice#recovers") do
      invoice.recovers
    end

    method_stats = stats["Billing::Invoice#recovers"]
    assert_equal 0, method_stats["raised_exits"]
    assert_equal({}, method_stats["raised"])
    assert_equal({ "Symbol" => 1 }, method_stats["returns"]["classes"])
  end

  def test_caller_is_recorded_as_file_and_line
    invoice = Invoice.new
    line = __LINE__ + 1
    stats = probe_and_read("Billing::Invoice#amount") { invoice.amount(1) }

    callers = stats["Billing::Invoice#amount"]["callers"]
    assert_equal 1, callers.size
    caller_key = callers.keys.first
    assert_includes caller_key, __FILE__
    assert_includes caller_key, ":#{line}:"
  end

  def test_calls_past_max_samples_are_tallied_but_not_serialized
    invoice = Invoice.new
    stats = probe_and_read("Billing::Invoice#amount") do
      15.times { |i| invoice.amount(i) }
    end

    returns = stats["Billing::Invoice#amount"]["returns"]
    assert_equal 15, returns["classes"]["Integer"]
    assert_equal 10, returns["samples"].size
    assert_equal 5, returns["samples_omitted"]
  end

  def test_config_max_samples_controls_the_serialization_cutoff
    invoice = Invoice.new
    Bulldogger.config.max_samples = 3

    stats = probe_and_read("Billing::Invoice#amount") do
      5.times { |i| invoice.amount(i) }
    end

    returns = stats["Billing::Invoice#amount"]["returns"]
    assert_equal 5, returns["classes"]["Integer"]
    assert_equal 3, returns["samples"].size
    assert_equal 2, returns["samples_omitted"]
  end

  def test_max_samples_is_published_in_the_evidence_limits
    invoice = Invoice.new
    Bulldogger.config.max_samples = 3

    path = Bulldogger.probe("Billing::Invoice#amount") { invoice.amount(1) }
    payload = JSON.parse(File.read(path))

    assert_equal 3, payload["limits"]["max_samples"]
    assert_equal File.join(Bulldogger.skill_path, "SKILL.md"), payload["skill"]
    assert File.file?(payload["skill"])
  end

  def test_a_parameter_named_like_a_secret_is_redacted_in_its_sample
    invoice = Invoice.new
    stats = probe_and_read("Billing::Invoice#charge") { invoice.charge("supersecret") }

    sample = stats["Billing::Invoice#charge"]["params"]["api_token"]["samples"].first
    assert_equal true, sample["redacted"]
    refute sample.key?("value")
    # The class tally is structural, not the secret's content -- it is
    # not gated by redaction, matching contract-verbs.md's "samples
    # are where secrets accumulate" (classes/nil_count are not
    # samples).
    assert_equal({ "String" => 1 }, stats["Billing::Invoice#charge"]["params"]["api_token"]["classes"])
  end

  private

  def probe_and_read(*targets, &block)
    path = Bulldogger.probe(*targets, &block)
    JSON.parse(File.read(path))["methods"]
  end
end
