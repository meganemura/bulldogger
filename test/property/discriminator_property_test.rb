# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../fixtures/property/nested_raise"

# The raise-exit discriminator (Probe::RaiseTracker) is what tells
# "this call returned nil" apart from "this call exited by raising"
# -- get it wrong and the tool fabricates a return the method never
# made.
# probe_capture_test.rb covers one level of nesting; this property
# generalizes to arbitrary nesting depth and arbitrary rescued/
# unrescued/re-raise combinations, for Probe::RaiseTracker.
class DiscriminatorPropertyTest < Minitest::Test
  Runner = NestedRaiseFixture::Runner
  Boom = NestedRaiseFixture::Boom

  def test_probe_raise_exit_discriminator_matches_actual_outcomes_across_nested_calls
    Hegel.test(test_cases: 25, suppress_health_check: [:too_slow]) do |tc|
      # Every draw happens before the probe session opens: probe's own
      # TracePoint is narrowly targeted, but keeping the traced region
      # to exactly the fixture calls (not hegel's own draw machinery)
      # matches the discipline record's half of this test needs, and
      # keeps the two halves symmetric.
      specs = tc.draw(spec_list_generator)
      nodes = specs.map { |wrappers, leaf| build_node(wrappers, leaf) }
      expected_flags = nodes.flat_map { |node| evaluate(node).last }

      path = Bulldogger.probe("NestedRaiseFixture::Runner.run") do
        nodes.each { |node| run_and_swallow(node) }
      end
      stats = JSON.parse(File.read(path))["methods"]["NestedRaiseFixture::Runner.run"]

      assert_equal expected_flags.size, stats["calls"]
      assert_equal expected_flags.count(true), stats["raised_exits"]
      assert_equal expected_flags.count(false), stats["returns"]["classes"].values.sum
      # The property's real reason to exist: a discriminator bug
      # fabricates a nil return for a call that actually raised. Every
      # leaf that returns normally here returns :ok or :recovered,
      # never nil -- so a nonzero nil_count is exactly a fabricated
      # return.
      assert_equal 0, stats["returns"]["nil_count"]
    end
  end

  private

  # One spec is (wrappers, leaf): wrappers is the chain from outermost
  # to innermost ("rescued" catches Boom and returns normally,
  # "unrescued" lets it propagate), leaf is how the innermost call
  # actually exits ("raise", "return", or "reraise" -- rescue then a
  # bare `raise`, the fixture's re-raise case; see nested_raise.rb).
  # max_size: 4 nests deep enough to exercise the checkpoint stack
  # across several frames without making each test case too slow to
  # shrink.
  def spec_list_generator
    arrays(
      tuples(
        arrays(sampled_from(%w[rescued unrescued]), min_size: 0, max_size: 4),
        sampled_from(%w[raise return reraise])
      ),
      min_size: 1, max_size: 5
    )
  end

  def build_node(wrappers, leaf)
    node = { "type" => leaf }
    wrappers.reverse_each { |wrapper| node = { "type" => wrapper, "inner" => node } }
    node
  end

  # Returns [this_node_raised, flags_for_every_call_innermost_first].
  # A "rescued" node always completes normally at its own level (it
  # catches whatever its inner call raised); an "unrescued" node
  # mirrors its inner call's own outcome exactly, since it neither
  # raises nor rescues anything itself.
  def evaluate(node)
    if node["inner"]
      inner_raised, inner_flags = evaluate(node["inner"])
      own_raised = node["type"] == "unrescued" ? inner_raised : false
      [own_raised, inner_flags + [own_raised]]
    else
      own_raised = node["type"] != "return"
      [own_raised, [own_raised]]
    end
  end

  def run_and_swallow(node)
    Runner.run(node)
  rescue Boom
    nil
  end
end
