# frozen_string_literal: true

require "test_helper"

# Bucket's real callers (MethodStats#record_call/#record_return) only
# ever call #record from inside the probe TracePoint hook, which
# stdlib Coverage cannot reliably observe (see test/unit/tracepoint_coverage_blind_spot_test.rb).
# #record takes a plain value, not a TracePoint, so it is fully
# testable directly.
class ProbeBucketTest < Minitest::Test
  def setup
    super
    @formatter = Bulldogger::Formatter.new(config: Bulldogger.config, redactor: Bulldogger::Redactor.new([]))
  end

  def test_record_tallies_class_names_and_nil_count
    bucket = Bulldogger::Probe::Bucket.new(formatter: @formatter, max_samples: 10)

    bucket.record(1)
    bucket.record("a")
    bucket.record(nil)

    h = bucket.to_h
    assert_equal({ "Integer" => 1, "String" => 1, "NilClass" => 1 }, h["classes"])
    assert_equal 1, h["nil_count"]
  end

  def test_samples_are_capped_and_the_omitted_count_is_reported
    bucket = Bulldogger::Probe::Bucket.new(formatter: @formatter, max_samples: 2)

    3.times { |i| bucket.record(i) }

    h = bucket.to_h
    assert_equal 2, h["samples"].size
    assert_equal 1, h["samples_omitted"]
  end

  def test_samples_omitted_is_absent_when_nothing_was_cut
    bucket = Bulldogger::Probe::Bucket.new(formatter: @formatter, max_samples: 10)

    bucket.record(1)

    refute bucket.to_h.key?("samples_omitted")
  end

  def test_a_redacted_name_bucket_records_redacted_placeholders_not_values
    bucket = Bulldogger::Probe::Bucket.new(formatter: @formatter, max_samples: 10, redacted_name: true)

    bucket.record("s3cr3t")

    sample = bucket.to_h["samples"].first
    assert_equal({ "redacted" => true, "reason" => "name" }, sample)
    # The class tally is structural, not gated by redaction (matches
    # probe_capture_test.rb's own behavioral assertion of the same
    # rule, reached here through the hook).
    assert_equal({ "String" => 1 }, bucket.to_h["classes"])
  end

  def test_merge_folds_another_buckets_tally_and_recaps_samples
    a = Bulldogger::Probe::Bucket.new(formatter: @formatter, max_samples: 2)
    b = Bulldogger::Probe::Bucket.new(formatter: @formatter, max_samples: 2)
    a.record(1)
    a.record(2)
    b.record(3)
    b.record(nil)

    a.merge!(b)

    h = a.to_h
    assert_equal({ "Integer" => 3, "NilClass" => 1 }, h["classes"])
    assert_equal 1, h["nil_count"]
    # Re-capped at max_samples even though merging pushed the total
    # past it -- each side already capped its own samples
    # independently, so the merge must not silently widen the limit.
    assert_equal 2, h["samples"].size
    assert_equal 2, h["samples_omitted"]
  end

  # safe_class_name's rescue branch: a value whose #class itself
  # raises (BasicObject-descended, or a poisoned singleton class).
  def test_a_value_whose_class_method_raises_is_tallied_as_object
    bucket = Bulldogger::Probe::Bucket.new(formatter: @formatter, max_samples: 10)
    poisoned = Object.new
    def poisoned.class
      raise "no class for you"
    end

    bucket.record(poisoned)

    assert_equal({ "Object" => 1 }, bucket.to_h["classes"])
  end
end
