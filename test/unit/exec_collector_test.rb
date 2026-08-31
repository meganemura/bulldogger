# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/real_trace_point"
require "stringio"

# ExecCollector's whole call/return/line group (dispatch, enter,
# leave, evaluate) only ever runs from inside the module's own gate or
# line TracePoint callback in production, which stdlib Coverage cannot
# reliably observe (see test/unit/tracepoint_coverage_blind_spot_test.rb).
# Every test below calls one of those private methods directly, with
# either a plain double or a binding captured outside any live
# callback (Bulldogger::TestSupport.capture_call_and_return), so
# Coverage sees the same lines run.
#
# ExecCollector is a module singleton, defined only when
# BULLDOGGER_EXEC/_OUT/_FID/_LINE/_VISIT/_STATEMENT are set at
# file-load time (production sets them in a spawned child process's
# environment, via RUBYOPT). This file sets them once, pointed at
# fixture_target below, and force-loads the module, then immediately
# disables its own live gate TracePoint so nothing here runs through
# it.
class ExecCollectorTest < Minitest::Test
  FID = "#{File.expand_path(__FILE__)}:fixture_target#1"

  def self.load_collector!
    return if defined?(Bulldogger::ExecCollector)

    output_dir = Dir.mktmpdir("bulldogger-exec-collector-test-")
    original_verbose = $VERBOSE
    $VERBOSE = nil
    ENV["BULLDOGGER_EXEC"] = "1"
    ENV["BULLDOGGER_EXEC_OUT"] = File.join(output_dir, "exec")
    ENV["BULLDOGGER_EXEC_FID"] = FID
    ENV["BULLDOGGER_EXEC_LINE"] = "1"
    ENV["BULLDOGGER_EXEC_VISIT"] = "1"
    ENV["BULLDOGGER_EXEC_STATEMENT"] = "1"
    load File.expand_path("../../lib/bulldogger/exec_collector.rb", __dir__)
  ensure
    %w[BULLDOGGER_EXEC BULLDOGGER_EXEC_OUT BULLDOGGER_EXEC_FID BULLDOGGER_EXEC_LINE
       BULLDOGGER_EXEC_VISIT BULLDOGGER_EXEC_STATEMENT].each { |name| ENV.delete(name) }
    $VERBOSE = original_verbose
  end

  load_collector!
  Bulldogger::ExecCollector.instance_variable_get(:@gate).disable

  def setup
    super
    @collector = Bulldogger::ExecCollector
    @io = StringIO.new
    @collector.instance_variable_set(:@file, @io)
    @collector.instance_variable_set(:@active, false)
    @collector.instance_variable_set(:@count, 0)
    @collector.instance_variable_set(:@observed_calls, 0)
    @collector.instance_variable_set(:@target_index, 1)
    @collector.instance_variable_set(:@target_reached, false)
    @collector.instance_variable_set(:@target_depth, 0)
    @collector.instance_variable_set(:@evaluated, false)
    @collector.instance_variable_set(:@visits, 0)
    @collector.instance_variable_set(:@target_line, 1)
    @collector.instance_variable_set(:@target_visit, 1)
    @collector.instance_variable_set(:@statement, "1")
    @collector.instance_variable_set(:@line_trace, nil)
  end

  def teardown
    @collector.send(:end_test)
    super
  end

  # --- dispatch --------------------------------------------------

  def test_dispatch_returns_early_when_inactive_off_path_or_off_method
    target_path = @collector.instance_variable_get(:@target_path)

    @collector.send(:dispatch, double(event: :call, path: target_path, method_id: :fixture_target))
    assert_empty written_records, "inactive dispatch must not record"

    @collector.instance_variable_set(:@active, true)
    @collector.send(:dispatch, double(event: :call, path: "/nowhere/else.rb", method_id: :fixture_target))
    assert_empty written_records, "off-path dispatch must not record"

    @collector.send(:dispatch, double(event: :call, path: target_path, method_id: :some_other_method))
    assert_empty written_records, "off-method dispatch must not record"
  end

  def test_dispatch_swallows_its_own_internal_failure_instead_of_raising
    @collector.instance_variable_set(:@active, true)

    @collector.send(:dispatch, double(event: :call, path: nil, method_id: :whatever))

    assert_empty written_records
  end

  def test_dispatch_routes_a_call_event_to_enter_and_a_non_call_event_to_leave
    call_double, return_double = Bulldogger::TestSupport.capture_call_and_return(method(:fixture_target)) { fixture_target(5) }
    @collector.instance_variable_set(:@active, true)

    @collector.send(:dispatch, call_double)
    refute_nil @collector.instance_variable_get(:@line_trace)

    @collector.send(:dispatch, return_double)
    assert_nil @collector.instance_variable_get(:@line_trace)
  end

  # --- enter -------------------------------------------------------

  def test_enter_increments_depth_without_rearming_when_already_tracing
    @collector.instance_variable_set(:@line_trace, TracePoint.new(:line) {})
    @collector.instance_variable_set(:@target_depth, 1)

    @collector.send(:enter, double(event: :call))

    assert_equal 2, @collector.instance_variable_get(:@target_depth)
    assert_equal 0, @collector.instance_variable_get(:@count)
  end

  def test_enter_does_not_arm_the_line_trace_before_the_target_index
    call_double, = Bulldogger::TestSupport.capture_call_and_return(method(:fixture_target)) { fixture_target(5) }
    @collector.instance_variable_set(:@target_index, 2)
    @collector.instance_variable_set(:@active, true)

    @collector.send(:enter, call_double)

    refute @collector.instance_variable_get(:@target_reached)
    assert_equal 1, @collector.instance_variable_get(:@count)
    assert_nil @collector.instance_variable_get(:@line_trace)
  end

  def test_enter_on_reaching_the_target_index_arms_the_line_trace
    call_double, = Bulldogger::TestSupport.capture_call_and_return(method(:fixture_target)) { fixture_target(5) }
    @collector.instance_variable_set(:@active, true)

    @collector.send(:enter, call_double)

    assert @collector.instance_variable_get(:@target_reached)
    assert_equal 1, @collector.instance_variable_get(:@target_depth)
    assert_equal 0, @collector.instance_variable_get(:@visits)
    refute @collector.instance_variable_get(:@evaluated)
    refute_nil @collector.instance_variable_get(:@line_trace)
  end

  # --- leave -------------------------------------------------------

  def test_leave_is_a_no_op_without_an_active_line_trace
    @collector.send(:leave)

    assert_empty written_records
  end

  def test_leave_only_decrements_depth_while_still_nested
    @collector.instance_variable_set(:@line_trace, TracePoint.new(:line) {})
    @collector.instance_variable_set(:@target_depth, 2)

    @collector.send(:leave)

    assert_equal 1, @collector.instance_variable_get(:@target_depth)
    assert_empty written_records
    refute_nil @collector.instance_variable_get(:@line_trace)
  end

  def test_leave_reports_the_evaluation_summary_when_the_line_never_evaluated
    @collector.instance_variable_set(:@line_trace, TracePoint.new(:line) {})
    @collector.instance_variable_set(:@target_depth, 1)
    @collector.instance_variable_set(:@evaluated, false)
    @collector.instance_variable_set(:@visits, 3)
    @collector.instance_variable_set(:@target_line, 10)
    @collector.instance_variable_set(:@target_visit, 5)

    @collector.send(:leave)

    record = written_records.first
    assert_equal "evaluation_summary", record["type"]
    assert_equal 3, record["line_visits_observed"]
    assert_equal 5, record["target_visit"]
    assert_equal false, record["evaluated"]
    assert_nil @collector.instance_variable_get(:@line_trace)
  end

  def test_leave_skips_the_summary_once_the_statement_already_evaluated
    @collector.instance_variable_set(:@line_trace, TracePoint.new(:line) {})
    @collector.instance_variable_set(:@target_depth, 1)
    @collector.instance_variable_set(:@evaluated, true)

    @collector.send(:leave)

    assert_empty written_records
    assert_nil @collector.instance_variable_get(:@line_trace)
  end

  # --- evaluate ------------------------------------------------------

  def test_evaluate_is_a_no_op_once_already_evaluated
    @collector.instance_variable_set(:@evaluated, true)

    @collector.send(:evaluate, double(event: :line, lineno: 1))

    assert_empty written_records
    assert_equal 0, @collector.instance_variable_get(:@visits)
  end

  def test_evaluate_ignores_lines_other_than_the_target_line
    @collector.instance_variable_set(:@target_line, 10)

    @collector.send(:evaluate, double(event: :line, lineno: 11))

    assert_equal 0, @collector.instance_variable_get(:@visits)
    assert_empty written_records
  end

  def test_evaluate_counts_a_visit_but_waits_for_the_target_visit
    @collector.instance_variable_set(:@target_line, 10)
    @collector.instance_variable_set(:@target_visit, 2)

    @collector.send(:evaluate, double(event: :line, lineno: 10))

    assert_equal 1, @collector.instance_variable_get(:@visits)
    refute @collector.instance_variable_get(:@evaluated)
    assert_empty written_records
  end

  def test_evaluate_writes_the_evaluated_value_on_the_target_visit
    @collector.instance_variable_set(:@target_line, 10)
    @collector.instance_variable_set(:@target_visit, 1)
    @collector.instance_variable_set(:@statement, "value * 2")
    target_binding = binding_fixture(21)

    @collector.send(:evaluate, double(event: :line, lineno: 10, binding: target_binding))

    record = written_records.first
    assert_equal "evaluation", record["type"]
    assert_equal({ "value" => "42" }, record["value"])
    assert @collector.instance_variable_get(:@evaluated)
  end

  def test_evaluate_records_the_exception_when_the_statement_raises
    @collector.instance_variable_set(:@target_line, 10)
    @collector.instance_variable_set(:@target_visit, 1)
    @collector.instance_variable_set(:@statement, "raise ArgumentError, 'boom'")
    target_binding = binding_fixture(1)

    @collector.send(:evaluate, double(event: :line, lineno: 10, binding: target_binding))

    record = written_records.first
    assert_equal "evaluation", record["type"]
    assert_equal "ArgumentError", record["exception_class"]
    assert_equal({ "value" => "\"boom\"" }, record["message"])
    assert @collector.instance_variable_get(:@evaluated)
  end

  private

  def double(**attributes)
    Bulldogger::TestSupport::Double.new(**attributes)
  end

  def written_records
    @io.string.each_line.map { |line| JSON.parse(line) }
  end

  # The target the FID constant above addresses. Its own file is this
  # test file, so a real :call/:return captured on it matches
  # @target_path/@target_method without any fixture app file.
  def fixture_target(value)
    total = value + 1
    total
  end

  def binding_fixture(value)
    binding
  end
end
