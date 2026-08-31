# frozen_string_literal: true

require_relative "../test_helper"
require "bulldogger/frames_collector"
require_relative "../support/real_trace_point"
require "stringio"

# FramesCollector's dispatch group (record, record_window_event,
# record_call, record_return, record_raise, normalize_method,
# application_path?) only ever runs from inside the module's own
# :call/:b_call/:return/:b_return/:raise TracePoint callback in
# production, which stdlib Coverage cannot reliably observe (see
# test/unit/tracepoint_coverage_blind_spot_test.rb). None of these
# methods read anything from a live TracePoint beyond the plain
# attributes TestSupport::Double already replays, so every test below
# calls them directly with a double instead of a live hook.
#
# FramesCollector is a module singleton, defined only when
# BULLDOGGER_FRAMES_OUT is set at file-load time (production sets it
# in a spawned child process's environment, via RUBYOPT). This file
# sets that variable once and force-loads the module, then immediately
# disables its own live TracePoint so nothing here runs through it.
class FramesCollectorTest < Minitest::Test
  def self.load_collector!
    return if defined?(Bulldogger::FramesCollector)

    output_dir = Dir.mktmpdir("bulldogger-frames-collector-test-")
    original_verbose = $VERBOSE
    $VERBOSE = nil
    ENV["BULLDOGGER_FRAMES_OUT"] = File.join(output_dir, "frames")
    load File.expand_path("../../lib/bulldogger/frames_collector.rb", __dir__)
  ensure
    ENV.delete("BULLDOGGER_FRAMES_OUT")
    $VERBOSE = original_verbose
  end

  load_collector!
  Bulldogger::FramesCollector.instance_variable_get(:@trace).disable

  def test_normalizes_the_complete_compiled_template_numeric_tail
    first = "_app_views_x_html_erb__4423017493750537167_15192"
    second = "_app_views_x_html_erb___2751381140246492290_99999"

    assert_equal Bulldogger::FramesMethod.normalize(first), Bulldogger::FramesMethod.normalize(second)
    assert_equal "push__2", Bulldogger::FramesMethod.normalize("push__2")
  end

  def setup
    super
    @collector = Bulldogger::FramesCollector
    @io = StringIO.new
    @collector.instance_variable_set(:@file, @io)
    @collector.instance_variable_set(:@stack, [])
    @collector.instance_variable_set(:@counts, Hash.new(0))
    @collector.instance_variable_set(:@raise_ordinal, 0)
    @collector.instance_variable_set(:@outside_window_events, 0)
    @collector.instance_variable_set(:@active, false)
  end

  def teardown
    @collector.instance_variable_set(:@active, false)
    @collector.instance_variable_set(:@stack, [])
    super
  end

  def test_active_predicate_reflects_begin_and_end_test
    refute @collector.active?

    @collector.begin_test
    assert @collector.active?

    @collector.end_test
    refute @collector.active?
  end

  def test_record_counts_events_outside_the_window_instead_of_recording_them
    @collector.send(:record, double(event: :call, path: __FILE__, method_id: :outside, lineno: 1))

    assert_equal 1, @collector.instance_variable_get(:@outside_window_events)
    assert_empty written_records
  end

  def test_record_swallows_its_own_internal_failure_instead_of_raising
    @collector.instance_variable_set(:@active, true)

    @collector.send(:record, double(event: :call, path: nil, method_id: :whatever, lineno: 1))

    assert_empty written_records
  end

  def test_record_window_event_skips_a_path_inside_the_collector_itself
    @collector.instance_variable_set(:@active, true)
    collector_path = File.join(Bulldogger::FramesCollector::COLLECTOR_DIR, "frames_collector.rb")

    @collector.send(:record, double(event: :call, path: collector_path, method_id: :internal, lineno: 1))

    assert_empty written_records
  end

  def test_record_window_event_expands_a_real_path_and_keeps_a_synthetic_one_verbatim
    @collector.instance_variable_set(:@active, true)

    @collector.send(:record, double(event: :call, path: "app/models/x.rb", method_id: :m, lineno: 1))
    @collector.send(:record, double(event: :call, path: "<internal:foo>", method_id: :m2, lineno: 1))

    real_frame, synthetic_frame = written_records
    assert_equal File.expand_path("app/models/x.rb"), real_frame["path"]
    assert_equal "<internal:foo>", synthetic_frame["path"]
  end

  def test_b_call_and_b_return_events_use_block_as_the_method_name
    @collector.instance_variable_set(:@active, true)

    @collector.send(:record, double(event: :b_call, path: __FILE__, method_id: nil, lineno: 1))
    @collector.send(:record, double(event: :b_return, path: __FILE__, method_id: nil, lineno: 2))

    call_record, return_record = written_records
    assert_equal "block", call_record["method"]
    assert_equal "block", return_record["method"]
  end

  def test_call_events_push_a_frame_and_record_the_parent_from_the_stack
    @collector.instance_variable_set(:@active, true)

    @collector.send(:record, double(event: :call, path: __FILE__, method_id: :outer, lineno: 10))
    @collector.send(:record, double(event: :call, path: __FILE__, method_id: :inner, lineno: 11))

    outer, inner = written_records
    assert_nil outer["parent"]
    assert_equal outer["fid"], inner["parent"]
    assert_equal 2, @collector.instance_variable_get(:@stack).size
  end

  def test_return_events_pop_the_matching_frame_and_write_its_close
    @collector.instance_variable_set(:@active, true)
    @collector.send(:record, double(event: :call, path: __FILE__, method_id: :m, lineno: 10))

    @collector.send(:record, double(event: :return, path: __FILE__, method_id: :m, lineno: 12))

    close = written_records.last
    assert_equal "return", close["type"]
    assert_empty @collector.instance_variable_get(:@stack)
  end

  def test_return_event_with_no_matching_frame_writes_nothing
    @collector.instance_variable_set(:@active, true)

    @collector.send(:record, double(event: :return, path: __FILE__, method_id: :never_called, lineno: 5))

    assert_empty written_records
  end

  def test_raise_events_number_themselves_and_name_the_exception_class
    @collector.instance_variable_set(:@active, true)
    error = RuntimeError.new("boom")

    @collector.send(:record, double(event: :raise, path: __FILE__, method_id: :m, lineno: 5, raised_exception: error))
    @collector.send(:record, double(event: :raise, path: __FILE__, method_id: :m, lineno: 6, raised_exception: error))

    first, second = written_records
    assert_equal 1, first["raise_ordinal"]
    assert_equal 2, second["raise_ordinal"]
    assert_equal "RuntimeError", first["exception_class"]
  end

  def test_normalize_method_names_a_blockless_method_id_block
    assert_equal "block", @collector.send(:normalize_method, nil)
    assert_equal "push__2", @collector.send(:normalize_method, :push__2)
  end

  def test_application_path_accepts_only_real_application_files_under_root
    root = @collector.instance_variable_get(:@root)

    assert @collector.send(:application_path?, "#{root}/lib/app.rb")
    refute @collector.send(:application_path?, "#{root}/vendor/bundle/gems/foo/lib/foo.rb")
    refute @collector.send(:application_path?, "/somewhere/else/lib/app.rb")
    refute @collector.send(:application_path?, "<internal:foo>")
  end

  private

  def double(**attributes)
    Bulldogger::TestSupport::Double.new(**attributes)
  end

  def written_records
    @io.string.each_line.map { |line| JSON.parse(line) }
  end
end
