# frozen_string_literal: true

require "test_helper"
require "json"

# Every value that reaches an evidence file has already passed through
# Formatter (a bounded String), so nothing in that JSON document should
# be lossy to write and read back. Draws arbitrary values into a real
# captured local, then checks that reading a real, written file back
# and running it through one more generate/parse cycle reproduces
# exactly the same Ruby structure -- the round trip contract.md holds
# evidence to.
class SchemaRoundtripPropertyTest < Minitest::Test
  def test_evidence_json_survives_a_second_generate_parse_cycle
    Hegel.test(test_cases: 40) do |tc|
      value = tc.draw(arbitrary_value_generator, label: "value")
      Bulldogger.start

      exception = trigger_with_value(value)
      path = Bulldogger.record_failure(
        exception: exception,
        test: { framework: "minitest", id: "x", file: "f.rb", line: 1 }
      )
      parsed_once = JSON.parse(File.read(path))
      parsed_twice = JSON.parse(JSON.generate(parsed_once))

      assert_equal parsed_once, parsed_twice
    end
  end

  private

  def arbitrary_value_generator
    one_of(
      integers(min_value: -1_000_000, max_value: 1_000_000),
      floats(min_value: -1_000.0, max_value: 1_000.0),
      # allow_nan/allow_infinity can only be set on an unbounded
      # floats() (hegel-ruby rejects the combination with min_value/
      # max_value at draw time) -- a separate, fully unbounded
      # generator is how this file still gets NaN/Infinity into a
      # captured value, the case most likely to break a naive
      # round-trip (JSON.generate raises on a real Float::NAN).
      floats(allow_nan: true, allow_infinity: true),
      text(min_size: 0, max_size: 300),
      booleans,
      just(nil),
      arrays(integers, min_size: 0, max_size: 15),
      hashes(text(max_size: 10), integers, min_size: 0, max_size: 10)
    )
  end

  def trigger_with_value(value)
    seeded = value
    [seeded] # read once so -w doesn't call it unused; capture reads it via binding, not this line
    raise "boom"
  rescue RuntimeError => e
    e
  end
end
