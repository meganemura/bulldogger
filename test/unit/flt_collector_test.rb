# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/real_trace_point"
require "stringio"

# FltCollector's whole call/return/line group (dispatch, enter, leave,
# line_dispatch, fold, flush_loop, emit_folded, snapshot, arguments,
# format_value) only ever runs from inside the module's own gate or
# line TracePoint callback in production, which stdlib Coverage cannot
# reliably observe (see test/unit/tracepoint_coverage_blind_spot_test.rb).
# Every test below calls one of those private methods directly, with
# either a plain double or a binding captured outside any live
# callback (Bulldogger::TestSupport.capture_call_and_return), so
# Coverage sees the same lines run.
#
# FltCollector is a module singleton, defined only when
# BULLDOGGER_FLT_OUT/_FID are set at file-load time (production sets
# them in a spawned child process's environment, via RUBYOPT). This
# file sets them once, pointed at fixture_target below, and
# force-loads the module, then immediately disables its own live gate
# TracePoint so nothing here runs through it.
class FltCollectorTest < Minitest::Test
  FID = "#{File.expand_path(__FILE__)}:fixture_target#1"

  def self.load_collector!
    return if defined?(Bulldogger::FltCollector)

    output_dir = Dir.mktmpdir("bulldogger-flt-collector-test-")
    original_verbose = $VERBOSE
    $VERBOSE = nil
    ENV["BULLDOGGER_FLT_OUT"] = File.join(output_dir, "flt")
    ENV["BULLDOGGER_FLT_FID"] = FID
    load File.expand_path("../../lib/bulldogger/flt_collector.rb", __dir__)
  ensure
    ENV.delete("BULLDOGGER_FLT_OUT")
    ENV.delete("BULLDOGGER_FLT_FID")
    $VERBOSE = original_verbose
  end

  load_collector!
  Bulldogger::FltCollector.instance_variable_get(:@gate).disable

  def setup
    super
    @collector = Bulldogger::FltCollector
    @io = StringIO.new
    @collector.instance_variable_set(:@file, @io)
    @collector.instance_variable_set(:@active, false)
    @collector.instance_variable_set(:@count, 0)
    @collector.instance_variable_set(:@observed_calls, 0)
    @collector.instance_variable_set(:@target_index, 1)
    @collector.instance_variable_set(:@target_reached, false)
    @collector.instance_variable_set(:@target_depth, 0)
    @collector.instance_variable_set(:@target_binding, nil)
    @collector.instance_variable_set(:@previous, nil)
    @collector.instance_variable_set(:@loops, nil)
    @collector.instance_variable_set(:@last_line, nil)
    @collector.instance_variable_set(:@line_trace, nil)
  end

  def teardown
    @collector.send(:finish_trace)
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

  def test_dispatch_routes_a_call_event_to_enter_and_a_return_event_to_leave
    call_double, return_double = Bulldogger::TestSupport.capture_call_and_return(method(:fixture_target)) { fixture_target(1) }
    @collector.instance_variable_set(:@active, true)

    @collector.send(:dispatch, call_double)
    @collector.send(:dispatch, return_double)

    assert_equal %w[call return], written_records.map { |record| record["type"] }
  end

  # --- enter -------------------------------------------------------

  def test_enter_increments_depth_without_resnapshotting_when_already_tracing
    @collector.instance_variable_set(:@line_trace, TracePoint.new(:line) {})
    @collector.instance_variable_set(:@target_depth, 1)

    @collector.send(:enter, double(event: :call))

    assert_equal 2, @collector.instance_variable_get(:@target_depth)
    assert_equal 0, @collector.instance_variable_get(:@count)
    assert_empty written_records
  end

  def test_enter_does_not_arm_the_line_trace_before_the_target_index
    call_double, = Bulldogger::TestSupport.capture_call_and_return(method(:fixture_target)) { fixture_target(1) }
    @collector.instance_variable_set(:@target_index, 2)
    @collector.instance_variable_set(:@active, true)

    @collector.send(:enter, call_double)

    refute @collector.instance_variable_get(:@target_reached)
    assert_equal 1, @collector.instance_variable_get(:@count)
    assert_nil @collector.instance_variable_get(:@line_trace)
    assert_empty written_records
  end

  def test_enter_on_reaching_the_target_index_snapshots_arguments_and_arms_the_line_trace
    call_double, = Bulldogger::TestSupport.capture_call_and_return(method(:fixture_target)) { fixture_target(1) }
    @collector.instance_variable_set(:@active, true)

    @collector.send(:enter, call_double)

    assert @collector.instance_variable_get(:@target_reached)
    assert_equal 1, @collector.instance_variable_get(:@target_depth)
    refute_nil @collector.instance_variable_get(:@line_trace)
    record = written_records.first
    assert_equal "call", record["type"]
    assert_equal({ "value" => "1" }, record.dig("args", "value"))
    assert_equal({ "value" => "[REDACTED]" }, record.dig("args", "password"))
  end

  # --- leave -------------------------------------------------------

  def test_leave_is_a_no_op_without_an_active_line_trace
    @collector.send(:leave, double(event: :return, return_value: nil))

    assert_empty written_records
  end

  def test_leave_only_decrements_depth_while_still_nested
    @collector.instance_variable_set(:@line_trace, TracePoint.new(:line) {})
    @collector.instance_variable_set(:@target_depth, 2)

    @collector.send(:leave, double(event: :return))

    assert_equal 1, @collector.instance_variable_get(:@target_depth)
    assert_empty written_records
    refute_nil @collector.instance_variable_get(:@line_trace)
  end

  def test_leave_finishes_the_trace_and_writes_the_formatted_return_value
    call_double, return_double = Bulldogger::TestSupport.capture_call_and_return(method(:fixture_target)) { fixture_target(1) }
    @collector.instance_variable_set(:@active, true)
    @collector.send(:enter, call_double)

    @collector.send(:leave, return_double)

    record = written_records.last
    assert_equal "return", record["type"]
    assert_equal({ "value" => "2" }, record["value"])
    assert_nil @collector.instance_variable_get(:@line_trace)
  end

  # --- line_dispatch -------------------------------------------------

  def test_line_dispatch_on_a_raise_event_writes_and_leaves_previous_untouched
    @collector.instance_variable_set(:@previous, { "a" => { "value" => "1" } })
    error = ArgumentError.new("boom")

    @collector.send(:line_dispatch, double(event: :raise, raised_exception: error))

    record = written_records.first
    assert_equal "raise", record["type"]
    assert_equal "ArgumentError", record["exception_class"]
    assert_equal({ "value" => "\"boom\"" }, record["message"])
    assert_equal({ "a" => { "value" => "1" } }, @collector.instance_variable_get(:@previous))
  end

  def test_line_dispatch_reports_new_changed_and_out_of_scope_locals
    current_binding = locals_fixture(x: 1, y: 2, z: 3)
    @collector.instance_variable_set(:@previous, {
                                        "x" => { "value" => "99" },
                                        "y" => { "value" => "2" },
                                        "w" => { "value" => "old" }
                                      })

    @collector.send(:line_dispatch, double(event: :line, lineno: 42, binding: current_binding))

    record = written_records.first
    assert_equal({ "z" => { "value" => "3" } }, record["new"])
    assert_equal({ "old" => { "value" => "99" }, "new" => { "value" => "1" } }, record.dig("changed", "x"))
    assert_equal ["w"], record["out_of_scope"]
    assert_equal(
      { "x" => { "value" => "1" }, "y" => { "value" => "2" }, "z" => { "value" => "3" } },
      @collector.instance_variable_get(:@previous)
    )
  end

  # --- fold / flush_loop / emit_folded --------------------------------

  def test_fold_emits_directly_when_no_loop_is_open
    @collector.send(:fold, { "type" => "line", "lineno" => 5 })

    assert_equal [{ "type" => "line", "lineno" => 5 }], written_records
    assert_nil @collector.instance_variable_get(:@loops)
    assert_equal 5, @collector.instance_variable_get(:@last_line)
  end

  def test_fold_opens_a_loop_when_the_line_number_goes_backward
    @collector.instance_variable_set(:@last_line, 11)

    @collector.send(:fold, { "type" => "line", "lineno" => 9 })

    loops = @collector.instance_variable_get(:@loops)
    assert_equal 1, loops.size
    assert_equal({ start: 9, end: 11, skipped: 0, buffer: [{ "type" => "line", "lineno" => 9 }] }, loops.first)
    assert_empty written_records
  end

  def test_fold_buffers_records_while_a_loop_is_open
    @collector.instance_variable_set(:@last_line, 9)
    @collector.instance_variable_set(:@loops, [{ start: 9, end: 11, skipped: 0, buffer: [] }])

    @collector.send(:fold, { "type" => "line", "lineno" => 10 })

    assert_empty written_records
    assert_equal [{ "type" => "line", "lineno" => 10 }], @collector.instance_variable_get(:@loops).last[:buffer]
  end

  def test_fold_replaces_the_buffer_and_counts_a_skip_when_the_loop_restarts
    loop_entry = { start: 9, end: 11, skipped: 0, buffer: [{ "lineno" => 10 }] }
    @collector.instance_variable_set(:@last_line, 11)
    @collector.instance_variable_set(:@loops, [loop_entry])

    @collector.send(:fold, { "type" => "line", "lineno" => 9 })

    assert_equal 1, loop_entry[:skipped]
    assert_equal [{ "type" => "line", "lineno" => 9 }], loop_entry[:buffer]
  end

  def test_fold_opens_a_nested_loop_when_the_line_falls_inside_the_outer_loop
    outer = { start: 9, end: 11, skipped: 0, buffer: [] }
    @collector.instance_variable_set(:@last_line, 11)
    @collector.instance_variable_set(:@loops, [outer])

    @collector.send(:fold, { "type" => "line", "lineno" => 10 })

    loops = @collector.instance_variable_get(:@loops)
    assert_equal 2, loops.size
    assert_equal({ start: 10, end: 11, skipped: 0, buffer: [{ "type" => "line", "lineno" => 10 }] }, loops.last)
  end

  def test_fold_flushes_a_loop_that_the_line_number_has_left
    loop_entry = { start: 9, end: 11, skipped: 2, buffer: [{ "type" => "line", "lineno" => 9 }] }
    @collector.instance_variable_set(:@last_line, 9)
    @collector.instance_variable_set(:@loops, [loop_entry])

    @collector.send(:fold, { "type" => "line", "lineno" => 13 })

    marker, buffered, current = written_records
    assert_equal "skipped_iterations", marker["type"]
    assert_equal 2, marker["count"]
    assert_equal 9, buffered["lineno"]
    assert_equal 13, current["lineno"]
    assert_empty @collector.instance_variable_get(:@loops)
  end

  def test_flush_loop_is_a_no_op_without_an_open_loop
    @collector.instance_variable_set(:@loops, nil)

    @collector.send(:flush_loop)

    assert_empty written_records
  end

  def test_flush_loop_skips_the_marker_when_nothing_was_skipped
    @collector.instance_variable_set(:@loops, [{ start: 9, end: 11, skipped: 0, buffer: [{ "type" => "line", "lineno" => 10 }] }])

    @collector.send(:flush_loop)

    assert_equal [{ "type" => "line", "lineno" => 10 }], written_records
  end

  def test_emit_folded_writes_directly_without_an_open_loop
    @collector.send(:emit_folded, { "type" => "line", "lineno" => 1 })

    assert_equal [{ "type" => "line", "lineno" => 1 }], written_records
  end

  def test_emit_folded_buffers_into_the_innermost_open_loop
    loop_entry = { start: 1, end: 2, skipped: 0, buffer: [] }
    @collector.instance_variable_set(:@loops, [loop_entry])

    @collector.send(:emit_folded, { "type" => "line", "lineno" => 2 })

    assert_empty written_records
    assert_equal [{ "type" => "line", "lineno" => 2 }], loop_entry[:buffer]
  end

  # --- snapshot / arguments / format_value ----------------------------

  def test_snapshot_formats_each_local_by_name
    target_binding = locals_fixture(x: "abc", y: 5, z: "keep")

    result = @collector.send(:snapshot, target_binding)

    assert_equal({ "value" => "5" }, result["y"])
    assert_equal({ "value" => "\"abc\"" }, result["x"])
  end

  def test_arguments_keeps_only_previous_keys_that_are_real_parameters
    target_binding = argument_fixture(1, "s3cr3t")
    @collector.instance_variable_set(:@previous, {
                                        "value" => { "value" => "1" },
                                        "password" => { "value" => "[REDACTED]" },
                                        "total" => { "value" => "2" }
                                      })

    result = @collector.send(:arguments, double(binding: target_binding))

    assert_equal({ "value" => { "value" => "1" }, "password" => { "value" => "[REDACTED]" } }, result)
  end

  def test_format_value_redacts_by_name_and_formats_otherwise
    assert_equal({ "value" => "[REDACTED]" }, @collector.send(:format_value, "session_token", "abc"))
    assert_equal({ "value" => "42" }, @collector.send(:format_value, "total", 42))
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
  def fixture_target(value, password: "secret")
    total = value + 1
    total
  end

  def argument_fixture(value, password)
    binding
  end

  def locals_fixture(x:, y:, z:)
    binding
  end
end
