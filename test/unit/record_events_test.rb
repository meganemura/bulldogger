# frozen_string_literal: true

require "test_helper"
require "bulldogger/record"
require "json"

class RecordEventsTest < Minitest::Test
  def test_call_return_and_raise_appear_as_one_json_line_each
    path = Bulldogger::Record.run do
      begin
        raise_and_exit
      rescue RuntimeError
        nil
      end
    end

    kinds = events(path).map { |e| e["event"] }
    assert_includes kinds, "call"
    assert_includes kinds, "return"
    assert_includes kinds, "raise"
    # Every line -- header and events -- must itself be one complete
    # JSON object: read_jsonl already calls JSON.parse per line, so
    # getting this far without a JSON::ParserError is the assertion.
    refute_empty read_jsonl(path)
  end

  # A global TracePoint is live for the entire process from #enable
  # onward, including the rest of Session's own constructor and the
  # entry into #stop -- both run this library's own lib/ code while
  # the trace point is already active. Without filtering those frames
  # out, every trace opened with "Session#initialize returned" (once
  # dumping this session's own Config#inspect) and closed with a
  # "Session#stop" call line; this asserts none of that leaks in.
  def test_no_event_names_a_path_inside_this_librarys_own_lib_directory
    path = Bulldogger::Record.run { plain_return(1) }

    lib_prefix = Bulldogger::FrameSource.default_skip_path_prefix
    leaked = events(path).select { |e| e["path"]&.start_with?(lib_prefix) }
    assert_empty leaked, "bulldogger's own frames must not appear in the trace"
  end

  def test_header_line_has_schema_version_kind_and_event_set
    path = Bulldogger::Record.run { plain_return(1) }

    header = read_jsonl(path).first
    assert_equal 1, header["schema_version"]
    assert_equal "record", header["kind"]
    assert_equal %w[call return raise], header["events"]
  end

  def test_actual_arguments_and_return_value_are_recorded
    path = Bulldogger::Record.run { plain_return(3, [1, 2, 3]) }

    call = find_event(path, "call", "plain_return")
    ret = find_event(path, "return", "plain_return")

    assert_equal({ "value" => "3" }, call["args"]["qty"])
    assert_equal({ "value" => "[1, 2, 3]" }, call["args"]["rows"])
    assert_equal({ "value" => "3" }, ret["return"])
  end

  def test_raise_exit_marks_raised_true_and_omits_the_return_key
    path = Bulldogger::Record.run do
      begin
        raise_and_exit
      rescue RuntimeError
        nil
      end
    end

    ret = find_event(path, "return", "raise_and_exit")
    assert_equal true, ret["raised"]
    refute ret.key?("return")
  end

  # Same discriminator, opposite outcome: a raise caught *inside* the
  # traced method must not be confused with one that exits it -- this
  # is the case the raw :raise-plus-1-forever counter would get wrong,
  # which is why the delta is taken at :return, not read as an
  # absolute value.
  def test_internal_rescue_records_as_a_normal_return
    path = Bulldogger::Record.run { raise_and_rescue }

    ret = find_event(path, "return", "raise_and_rescue")
    refute ret.key?("raised")
    assert_equal({ "value" => ":recovered" }, ret["return"])
  end

  def test_api_token_named_argument_is_redacted
    path = Bulldogger::Record.run { with_secret("s3cr3t") }

    call = find_event(path, "call", "with_secret")
    assert_equal({ "redacted" => true, "reason" => "name" }, call["args"]["api_token"])
    refute call["args"]["api_token"].key?("value")
  end

  def test_huge_value_is_truncated_and_the_cut_is_marked
    path = Bulldogger::Record.run { plain_return("a" * 5000, []) }

    entry = find_event(path, "call", "plain_return")["args"]["qty"]
    assert entry["truncated"]
    assert entry["original_length"]
  end

  def test_stop_is_idempotent
    session = Bulldogger::Record.start
    plain_return(1)

    first = session.stop
    second = session.stop

    assert_equal first, second
  end

  def test_disabled_switch_returns_nil_writes_nothing_but_still_runs_the_block
    original = ENV["BULLDOGGER_DISABLE"]
    ENV["BULLDOGGER_DISABLE"] = "1"
    bulldogger_reset!
    ran = false

    path = Bulldogger::Record.run { ran = plain_return(1) == 1 }

    assert_nil path
    assert ran, "the block must still execute even when recording is disabled"
    assert_empty Dir.glob(File.join(Bulldogger.config.output_dir, "run-*"))
  ensure
    ENV["BULLDOGGER_DISABLE"] = original
  end

  # Breaking Formatter (used by every :call/:return line) simulates
  # the hook itself failing; the traced method's own return value must
  # still come back to the caller unharmed, the same guarantee
  # Capture's :raise hook makes. Patches the one Formatter instance
  # this session builds, not the class -- same technique
  # capture_test.rb uses, and it avoids a class-wide method
  # redefinition warning under `ruby -w`.
  def test_hook_failure_does_not_break_the_traced_code
    session = Bulldogger::Record.start
    formatter = session.instance_variable_get(:@formatter)
    def formatter.format(*)
      raise "formatter exploded"
    end

    result = plain_return(7)
    session.stop

    assert_equal 7, result
  end

  private

  def plain_return(qty, rows = [1, 2, 3])
    rows.length # touch rows so it is a real local at :call, not just declared
    qty
  end

  def with_secret(api_token)
    api_token.length
  end

  def raise_and_exit
    raise "boom"
  end

  def raise_and_rescue
    raise "boom"
  rescue RuntimeError
    :recovered
  end

  def read_jsonl(path)
    File.readlines(path).map { |line| JSON.parse(line) }
  end

  def events(path)
    read_jsonl(path).drop(1)
  end

  def find_event(path, event, method_fragment)
    events(path).find { |e| e["event"] == event && e["method"].to_s.include?(method_fragment) }
  end
end
