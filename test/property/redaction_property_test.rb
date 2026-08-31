# frozen_string_literal: true

require "test_helper"

# Generalizes redactor_test.rb's hand-picked names/values to arbitrary
# ones, at the two places redaction gates on a *name*, not a value:
#
#   - a Hash key's own to_s (Formatter#render_pair): the key itself is
#     an ordinary value, so it can be hegel-drawn directly, matching
#     both a matching and a non-matching name.
#   - a captured local's name (Capture -> FrameSource -> Redactor):
#     Ruby local variable names are fixed at parse time, so they
#     cannot be hegel-drawn the same way a Hash key can. This half
#     keeps the *names* fixed (one known to match a default pattern,
#     one known not to) and draws arbitrary *values* instead --
#     the honest ceiling of what a real, running local variable
#     allows, upgrading redactor_test.rb's fixed-string values to
#     arbitrary ones.
class RedactionPropertyTest < Minitest::Test
  MATCHING_KEY_NAMES = %w[password secret_token api_key auth_flag session_id cookie_value credential_hash].freeze
  NON_MATCHING_KEY_NAMES = %w[count name total x description qty amount].freeze

  def test_hash_value_is_redacted_exactly_when_its_key_name_matches
    Hegel.test(test_cases: 80) do |tc|
      matches = tc.draw(booleans, label: "matches")
      key = matches ? tc.draw(sampled_from(MATCHING_KEY_NAMES)) : tc.draw(sampled_from(NON_MATCHING_KEY_NAMES))
      value = tc.draw(arbitrary_scalar_generator, label: "value")
      formatter = build_formatter

      entry = formatter.format({ key => value })

      expected = matches ? "{#{key.inspect} => \"[REDACTED]\"}" : "{#{key.inspect} => #{value.inspect}}"
      assert_equal expected, entry["value"]
    end
  end

  def test_local_is_redacted_exactly_when_its_name_matches_regardless_of_value
    Hegel.test(test_cases: 60) do |tc|
      secret_value = tc.draw(arbitrary_scalar_generator, label: "secret_value")
      plain_value = tc.draw(arbitrary_scalar_generator, label: "plain_value")
      Bulldogger.start

      exception = trigger_with_locals(secret_value, plain_value)
      locals = Bulldogger.snapshot_for(exception)["frames"][0]["locals"]

      secret_entry = locals.fetch("api_token")
      assert_equal true, secret_entry["redacted"]
      assert_equal "name", secret_entry["reason"]
      refute secret_entry.key?("value")

      plain_entry = locals.fetch("count")
      assert plain_entry.key?("value")
      refute plain_entry.key?("redacted")
    end
  end

  private

  # Kept to values whose #inspect the test can recompute independently
  # of Formatter (plain scalars: Formatter's own render_nested calls
  # #inspect directly on all of these, with no further expansion), so
  # the expected string in the Hash-key test above is a real oracle,
  # not a restatement of the code under test.
  def arbitrary_scalar_generator
    one_of(
      integers(min_value: -1000, max_value: 1000),
      floats(min_value: -1000.0, max_value: 1000.0),
      text(min_size: 0, max_size: 20),
      booleans,
      just(nil),
      sampled_from(%i[a b sym])
    )
  end

  def build_formatter
    config = Bulldogger::Config.new
    redactor = Bulldogger::Redactor.new(config.redact_patterns)
    Bulldogger::Formatter.new(config: config, redactor: redactor)
  end

  def trigger_with_locals(secret_value, plain_value)
    api_token = secret_value
    count = plain_value
    [api_token, count] # read once so -w doesn't call these unused; capture reads them via binding, not this line
    raise "boom"
  rescue RuntimeError => e
    e
  end
end
