# frozen_string_literal: true

require "test_helper"

class FormatterTest < Minitest::Test
  class ExplodingInspect
    def inspect
      raise RuntimeError, "boom"
    end
  end

  class BasicObjectThing < BasicObject
  end

  def test_long_string_is_truncated_and_marked
    formatter = build_formatter(max_value_length: 200)
    long_value = "a" * 5000

    entry = formatter.format(long_value)

    assert entry["truncated"]
    assert_equal long_value.inspect.length, entry["original_length"]
    assert_equal 201, entry["value"].length
  end

  def test_short_value_has_no_truncation_keys
    formatter = build_formatter(max_value_length: 200)

    entry = formatter.format(3)

    refute entry.key?("truncated")
    refute entry.key?("original_length")
  end

  def test_broken_inspect_does_not_raise
    formatter = build_formatter

    entry = formatter.format(ExplodingInspect.new)

    assert_match(/\A#<FormatterTest::ExplodingInspect \(inspect raised RuntimeError\)>/, entry["value"])
  end

  def test_basic_object_does_not_raise
    formatter = build_formatter

    entry = formatter.format(BasicObjectThing.new)

    assert_match(/\A#</, entry["value"])
  end

  def test_array_and_hash_expand_one_level_only
    formatter = build_formatter

    entry = formatter.format([1, [2, 3], { "a" => 1 }, "x"])

    assert_includes entry["value"], "[…]"
    assert_includes entry["value"], "{…}"
  end

  def test_array_is_cut_at_ten_elements
    formatter = build_formatter

    entry = formatter.format((1..15).to_a)

    assert_includes entry["value"], "…"
    refute_includes entry["value"], "15"
  end

  private

  def build_formatter(max_value_length: 200, redact_patterns: Bulldogger::Config::DEFAULT_REDACT_PATTERNS)
    config = Bulldogger::Config.new
    config.max_value_length = max_value_length
    config.redact_patterns = redact_patterns
    Bulldogger::Formatter.new(config: config, redactor: Bulldogger::Redactor.new(config.redact_patterns))
  end
end
