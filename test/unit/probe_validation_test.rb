# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../fixtures/probe/target_app"

class ProbeValidationTest < Minitest::Test
  def test_all_targets_are_resolved_before_any_instrumentation_starts
    ran = false
    assert_raises(NameError) do
      Bulldogger.probe("Billing::Invoice#nope") { ran = true }
    end
    refute ran, "the block must never run when a target fails to resolve"
  end

  def test_unknown_method_name_fails_with_the_target_name_in_the_message
    error = assert_raises(NameError) { Bulldogger.probe_start("Billing::Invoice#nope") }
    assert_includes error.message, "Billing::Invoice#nope"
  end

  def test_c_implemented_method_fails_with_the_target_name_in_the_message
    error = assert_raises(ArgumentError) { Bulldogger.probe_start("Array#push") }
    assert_includes error.message, "Array#push"
  end

  def test_probing_an_already_probed_target_fails_with_its_name_in_the_message
    session = Bulldogger.probe_start("Billing::Invoice#amount")
    begin
      error = assert_raises(ArgumentError) { Bulldogger.probe_start("Billing::Invoice#amount") }
      assert_includes error.message, "Billing::Invoice#amount"
    ensure
      session.finish
    end
  end

  def test_disabled_switch_returns_nil_and_writes_nothing_but_still_runs_the_block
    Bulldogger.config.enabled = false
    ran = false

    result = Bulldogger.probe("Billing::Invoice#amount") do
      ran = true
      :block_return_value_must_not_leak_through
    end

    assert_nil result
    assert ran, "the app's own code must still run when the switch is off"
    assert_empty Dir.glob(File.join(Bulldogger.config.output_dir, "run-*")),
                 "a disabled switch must not create a run directory, let alone write a file into it"
  end

  def test_disabled_switch_makes_probe_start_return_nil
    Bulldogger.config.enabled = false

    assert_nil Bulldogger.probe_start("Billing::Invoice#amount")
  end

  def test_a_broken_formatter_does_not_break_the_probed_app_code
    invoice = Billing::Invoice.new
    session = Bulldogger.probe_start("Billing::Invoice#amount")
    formatter = session.instance_variable_get(:@formatter)
    def formatter.format(*)
      raise "formatter exploded"
    end

    begin
      result = invoice.amount(3)
      assert_equal 30, result, "the hook's own failure must not corrupt the app's return value"
    ensure
      session.finish
    end
  end

  # A block-form probe whose block raises unwinds through the ensure
  # in Session.run: session.finish releases RaiseTracker before the
  # matching :rescue back at this test's own assert_raises ever fires,
  # so this fiber's raise/rescue counter is left unbalanced on
  # purpose. A later, unrelated session on the same fiber must not
  # misread that leftover imbalance as its own raise-exit -- this is
  # exactly what RaiseTracker's delta (not absolute counter) design
  # exists to prevent.
  def test_a_raise_that_escapes_a_finished_session_does_not_poison_a_later_session
    invoice = Billing::Invoice.new

    assert_raises(ArgumentError) do
      Bulldogger.probe("Billing::Invoice#blows_up") { invoice.blows_up }
    end

    path = Bulldogger.probe("Billing::Invoice#amount") { invoice.amount(3) }
    stats = JSON.parse(File.read(path))["methods"]["Billing::Invoice#amount"]

    assert_equal 0, stats["raised_exits"]
    assert_equal({ "Integer" => 1 }, stats["returns"]["classes"])
  end
end
