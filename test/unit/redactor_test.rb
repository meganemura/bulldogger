# frozen_string_literal: true

require "test_helper"

class RedactorTest < Minitest::Test
  class InspectSpy
    attr_reader :inspected

    def initialize
      @inspected = false
    end

    def inspect
      @inspected = true
      "#<InspectSpy>"
    end
  end

  def test_locals_matching_a_pattern_are_redacted_without_a_value
    Bulldogger.start

    exception = trigger_secret_locals
    locals = Bulldogger.snapshot_for(exception)["frames"][0]["locals"]

    %w[secret_token password api_key].each do |name|
      entry = locals.fetch(name)
      assert_equal true, entry["redacted"]
      assert_equal "name", entry["reason"]
      refute entry.key?("value")
    end
  end

  def test_hash_values_are_redacted_by_key_name
    config = Bulldogger::Config.new
    redactor = Bulldogger::Redactor.new(config.redact_patterns)
    formatter = Bulldogger::Formatter.new(config: config, redactor: redactor)

    entry = formatter.format({ "PASSWORD" => "hunter2" })

    assert_includes entry["value"], "[REDACTED]"
    refute_includes entry["value"], "hunter2"
  end

  def test_redacted_locals_never_call_inspect
    # Named secret_thing here too, not just in the callee: this test's
    # own frame is captured along with the callee's, and any name that
    # does not match a redact pattern -- even in an unrelated frame --
    # would get formatted, calling #inspect on the same object.
    secret_thing = InspectSpy.new
    Bulldogger.start

    trigger_secret_thing(secret_thing)

    refute secret_thing.inspected
  end

  private

  def trigger_secret_locals
    secret_token = "s3cr3t"
    password = "hunter2"
    api_key = "abc123"
    [secret_token, password, api_key] # read once so -w doesn't call these unused; capture reads them via binding, not this line
    raise "boom"
  rescue RuntimeError => e
    e
  end

  def trigger_secret_thing(secret_thing)
    raise "boom"
  rescue RuntimeError => e
    e
  end
end
