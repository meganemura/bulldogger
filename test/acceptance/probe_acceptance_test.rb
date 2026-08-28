# frozen_string_literal: true

require_relative "acceptance_helper"
require "minitest/autorun"
require "json"

class ProbeAcceptanceTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  FIXTURE = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/probe/acceptance_app.rb")

  def test_probing_a_real_child_process_app_writes_the_seeded_shape
    stdout, stderr, status, output_dir = run_fixture("ruby", FIXTURE)

    assert status.success?, "fixture failed: #{stderr}"
    path = stdout[%r{probe evidence: (/\S+\.json)}, 1]
    refute_nil path, "no probe evidence path in stdout:\n#{stdout}"
    assert File.exist?(path)

    files = probe_evidence_files(output_dir)
    assert_equal [path], files, "exactly one probe-*.json, matching the printed path"

    data = JSON.parse(File.read(path))
    assert_equal 1, data["schema_version"]
    assert_equal "probe", data["kind"]

    amount = data.dig("methods", "Billing::Invoice#amount")
    refute_nil amount
    assert_equal 2, amount["calls"]
    assert_equal [%w[req mult], ["key", "discount"]], amount["parameters"]
    assert_equal({ "value" => "3" }, amount.dig("params", "mult", "samples", 0))
    assert_equal 1, amount.dig("params", "discount", "nil_count")
    assert_equal({ "Integer" => 2 }, amount.dig("returns", "classes"))
    caller_key = amount["callers"].keys.first
    assert_includes caller_key, "call_amount"

    charge = data.dig("methods", "Billing::Invoice#charge")
    sample = charge.dig("params", "api_token", "samples", 0)
    assert_equal true, sample["redacted"]
    refute sample.key?("value")
  end

  private

  def probe_evidence_files(output_dir)
    Dir.glob(File.join(output_dir, "run-*", "probe-*.json"))
  end
end
