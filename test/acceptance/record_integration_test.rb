# frozen_string_literal: true

require_relative "acceptance_helper"
require "minitest/autorun"
require "json"

class RecordIntegrationTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  FIXTURE = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/record/run.rb")

  def test_records_seeded_arguments_return_value_and_exception
    stdout, stderr, status, _output_dir = run_fixture("ruby", FIXTURE)

    assert status.success?, "fixture script is expected to exit 0:\nstdout: #{stdout}\nstderr: #{stderr}"
    path = stdout[/BULLDOGGER_TRACE: (\S+)/, 1]
    refute_nil path, "fixture did not print a trace path:\n#{stdout}"
    assert File.absolute_path?(path)
    assert File.exist?(path)

    lines = File.readlines(path).map { |line| JSON.parse(line) }
    header = lines.first
    events = lines.drop(1)

    assert_equal 1, header["schema_version"]
    assert_equal "record", header["kind"]
    assert_equal %w[call return raise], header["events"]

    assert_seeded_call(events)
    assert_seeded_return(events)
    assert_seeded_raise(events)
  end

  private

  def assert_seeded_call(events)
    call = events.find { |e| e["event"] == "call" && e["method"] == "Billing.total" }
    refute_nil call, "no call event for Billing.total"
    assert_equal({ "value" => "3" }, call["args"]["qty"])
    assert_equal({ "value" => "4" }, call["args"]["price"])
    assert_equal true, call.dig("args", "api_token", "redacted")
    refute call["args"]["api_token"].key?("value")
  end

  def assert_seeded_return(events)
    ret = events.find { |e| e["event"] == "return" && e["method"] == "Billing.total" }
    refute_nil ret, "no return event for Billing.total"
    assert_equal({ "value" => "12" }, ret["return"])
  end

  def assert_seeded_raise(events)
    raised = events.find { |e| e["event"] == "raise" && e["method"] == "Billing.total!" }
    refute_nil raised, "no raise event for Billing.total!"
    assert_equal "ArgumentError", raised["exception"]["class"]
    assert_includes raised["exception"]["message"], "qty must be positive"

    exited_return = events.find { |e| e["event"] == "return" && e["method"] == "Billing.total!" }
    refute_nil exited_return, "no return event for the raise-exit"
    assert_equal true, exited_return["raised"]
    refute exited_return.key?("return")
  end
end
