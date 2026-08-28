# frozen_string_literal: true

require "test_helper"

# Generalizes formatter_test.rb's hand-picked "long string is
# truncated and marked" / "short value has no truncation keys" cases
# to arbitrary values and arbitrary max_value_length: the bound
# (never more than max_value_length + 1 characters) and the
# "truncated iff cut, both truncated/original_length or neither"
# biconditional must hold together, or a reader loses the ability to
# trust the absence of those keys as "nothing was cut" (contract.md).
#
# Checking the bounded entry against itself alone is not enough: a
# formatter that silently chopped a value to fit, without ever
# setting "truncated", would satisfy a self-consistency-only check
# (this was caught by this file's own falsification run -- see the
# task report). ORACLE_MAX_VALUE_LENGTH gives an independent ground
# truth -- the same value's *un*truncated rendering -- so the
# assertions below compare the bounded entry against what actually
# happened, not just against its own claimed state.
class FormatterPropertyTest < Minitest::Test
  # Comfortably above the longest string arbitrary_value_generator can
  # produce (worst case: 400 text characters, each escaped up to
  # ~\uXXXX by #inspect, well under five figures), so a formatter
  # built with this bound never truncates -- it is the "what would
  # this have rendered as, with no limit" oracle.
  ORACLE_MAX_VALUE_LENGTH = 1_000_000

  def test_formatted_value_stays_within_bound_and_marks_every_cut_both_ways
    Hegel.test(test_cases: 150) do |tc|
      max_value_length = tc.draw(integers(min_value: 0, max_value: 300), label: "max_value_length")
      value = tc.draw(arbitrary_value_generator, label: "value")

      full_entry = build_formatter(ORACLE_MAX_VALUE_LENGTH).format(value)
      refute full_entry.key?("truncated"), "the oracle bound itself must never truncate: #{full_entry.inspect}"
      full_value = full_entry["value"]

      bounded_entry = build_formatter(max_value_length).format(value)

      assert_operator bounded_entry["value"].length, :<=, max_value_length + 1

      if full_value.length > max_value_length
        assert bounded_entry.key?("truncated"), "expected a cut: full value was #{full_value.inspect}"
        assert_equal full_value.length, bounded_entry["original_length"]
        assert_equal max_value_length + 1, bounded_entry["value"].length
        assert_equal "#{full_value[0, max_value_length]}…", bounded_entry["value"]
      else
        refute bounded_entry.key?("truncated")
        refute bounded_entry.key?("original_length")
        assert_equal full_value, bounded_entry["value"]
      end
    end
  end

  private

  def arbitrary_value_generator
    one_of(
      integers(min_value: -1_000_000, max_value: 1_000_000),
      floats(min_value: -1_000.0, max_value: 1_000.0),
      text(min_size: 0, max_size: 400),
      booleans,
      just(nil),
      sampled_from(%i[a_symbol another_symbol]),
      arrays(integers(min_value: 0, max_value: 100), min_size: 0, max_size: 20),
      hashes(text(max_size: 10), integers, min_size: 0, max_size: 10)
    )
  end

  def build_formatter(max_value_length)
    config = Bulldogger::Config.new
    config.max_value_length = max_value_length
    redactor = Bulldogger::Redactor.new(config.redact_patterns)
    Bulldogger::Formatter.new(config: config, redactor: redactor)
  end
end
