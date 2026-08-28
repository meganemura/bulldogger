# frozen_string_literal: true

require "test_helper"
require_relative "../support/real_trace_point"
require_relative "../fixtures/probe/target_app"

# MethodStats' real caller (Probe::Session's dispatch) only ever calls
# #record_call/#record_return from inside the probe TracePoint hook,
# which stdlib Coverage cannot reliably observe (see test/unit/tracepoint_coverage_blind_spot_test.rb).
# Both take a TracePoint argument, so these use a double built from a
# real call/return instead of a live hook.
class ProbeMethodStatsTest < Minitest::Test
  def setup
    super
    @redactor = Bulldogger::Redactor.new(Bulldogger.config.redact_patterns)
    @formatter = Bulldogger::Formatter.new(config: Bulldogger.config, redactor: @redactor)
  end

  def test_record_call_and_record_return_tally_a_real_invocation
    stats = build_stats("Billing::Invoice#amount", :amount)
    invoice = Billing::Invoice.new
    caller_loc = caller_locations(1, 1)&.first

    call_tp, return_tp = Bulldogger::TestSupport.capture_call_and_return(unbound(:amount)) { invoice.amount(4) }
    stats.record_call(call_tp, caller_loc)
    stats.record_return(return_tp, raised: false)

    h = stats.to_h
    assert_equal 1, h["calls"]
    assert_equal 0, h["raised_exits"]
    assert_equal({ "value" => "4" }, h["params"]["mult"]["samples"].first)
    assert_equal({ "value" => "nil" }, h["params"]["discount"]["samples"].first)
    assert_equal({ "Integer" => 1 }, h["returns"]["classes"])
    assert_equal 1, h["callers"].values.sum
  end

  def test_record_call_with_no_caller_location_records_nothing_for_callers
    stats = build_stats("Billing::Invoice#amount", :amount)
    invoice = Billing::Invoice.new

    call_tp, = Bulldogger::TestSupport.capture_call_and_return(unbound(:amount)) { invoice.amount(1) }
    stats.record_call(call_tp, nil)

    assert_empty stats.to_h["callers"]
  end

  def test_two_calls_from_the_same_call_site_tally_under_one_caller_entry
    stats = build_stats("Billing::Invoice#amount", :amount)
    invoice = Billing::Invoice.new
    caller_loc = caller_locations(1, 1)&.first

    2.times do
      call_tp, = Bulldogger::TestSupport.capture_call_and_return(unbound(:amount)) { invoice.amount(1) }
      stats.record_call(call_tp, caller_loc)
    end

    callers = stats.to_h["callers"]
    assert_equal 1, callers.size
    assert_equal 2, callers.values.first
  end

  # raised: true means the raise-exit discriminator fired for this
  # return -- must tally as a raise, never fabricate a nil return.
  def test_record_return_with_raised_true_tallies_a_raise_exit_not_a_return
    stats = build_stats("Billing::Invoice#blows_up", :blows_up)
    invoice = Billing::Invoice.new

    _call_tp, return_tp = Bulldogger::TestSupport.capture_call_and_return(unbound(:blows_up)) do
      begin
        invoice.blows_up
      rescue ArgumentError
        nil
      end
    end
    stats.record_return(return_tp, raised: true)

    h = stats.to_h
    assert_equal 1, h["raised_exits"]
    assert_equal 0, h["returns"]["classes"].values.sum
    assert_equal 0, h["returns"]["nil_count"]
  end

  def test_a_parameter_named_like_a_secret_is_redacted_when_recorded_directly
    stats = build_stats("Billing::Invoice#charge", :charge)
    invoice = Billing::Invoice.new

    call_tp, = Bulldogger::TestSupport.capture_call_and_return(unbound(:charge)) { invoice.charge("s3cr3t") }
    stats.record_call(call_tp, nil)

    sample = stats.to_h["params"]["api_token"]["samples"].first
    assert_equal true, sample["redacted"]
  end

  private

  def build_stats(label, method_name)
    target = Bulldogger::Probe::Target.new(label, unbound(method_name))
    Bulldogger::Probe::MethodStats.new(target: target, formatter: @formatter, redactor: @redactor, max_samples: 10)
  end

  def unbound(method_name)
    Billing::Invoice.instance_method(method_name)
  end
end
