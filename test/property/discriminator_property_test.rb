# frozen_string_literal: true

require "test_helper"
require "bulldogger/record"
require "json"
require_relative "../fixtures/property/nested_raise"

# The raise-exit discriminator (contract-verbs.md) is what tells "this
# call returned nil" apart from "this call exited by raising" -- get
# it wrong and the tool fabricates a return the method never made.
# Hand-picked cases (probe_capture_test.rb, record_events_test.rb)
# cover one level of nesting each; this property generalizes to
# arbitrary nesting depth and arbitrary rescued/unrescued/re-raise
# combinations, for both implementations that carry this logic
# independently (Probe::RaiseTracker and Record::Session's own
# counter).
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

  def test_record_raise_exit_discriminator_matches_actual_outcomes_across_nested_calls
    Hegel.test(test_cases: 20, suppress_health_check: [:too_slow]) do |tc|
      specs = tc.draw(spec_list_generator)
      nodes = specs.map { |wrappers, leaf| build_node(wrappers, leaf) }
      # evaluate's own flag order (innermost node first) matches the
      # order :return events fire in a real call stack unwind, and
      # nodes are run strictly one after another, so concatenating in
      # node order matches the trace's own seq order too.
      expected_flags = nodes.flat_map { |node| evaluate(node).last }

      path = Bulldogger::Record.run { nodes.each { |node| run_and_swallow(node) } }
      # select/map, not filter_map: filter_map drops a block result of
      # exactly `false` (it keeps only truthy results), which would
      # silently discard every non-raised return event -- exactly the
      # normal-return case this property most needs to see.
      events = File.readlines(path).drop(1).map { |line| JSON.parse(line) }
      actual_flags = events
                     .select { |event| event["event"] == "return" && event["method"] == "NestedRaiseFixture::Runner.run" }
                     .map { |event| event.key?("raised") }

      assert_equal expected_flags, actual_flags
    end
  end

  private

  # One spec is (wrappers, leaf): wrappers is the chain from outermost
  # to innermost ("rescued" catches Boom and returns normally,
  # "unrescued" lets it propagate), leaf is how the innermost call
  # actually exits ("raise", "return", or "reraise" -- rescue then a
  # bare `raise`, contract-verbs.md's re-raise case). max_size: 4
  # nests deep enough to exercise the checkpoint stack across several
  # frames without making each test case too slow to shrink.
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
