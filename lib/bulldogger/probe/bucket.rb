# frozen_string_literal: true

module Bulldogger
  module Probe
    # One params[name]/returns aggregate: a running tally of observed
    # classes and nil-ness (updated on every call), plus a bounded,
    # fully-serialized sample of the first max_samples values.
    #
    # Tally and sample are deliberately split: full serialization
    # measures ~24us/event, which would blow the probe overhead budget
    # on a call-dense target if it ran on every call. Class name and
    # nil? never touch #inspect, so the tally stays cheap regardless
    # of how many calls a session sees.
    class Bucket
      def initialize(formatter:, max_samples:, redacted_name: false)
        @formatter = formatter
        @max_samples = max_samples
        @redacted_name = redacted_name
        @classes = Hash.new(0)
        @nil_count = 0
        @samples = []
        @count = 0
      end

      def record(value)
        @count += 1
        @classes[safe_class_name(value)] += 1
        @nil_count += 1 if value.nil?
        @samples << sample_for(value) if @samples.size < @max_samples
      end

      def to_h
        h = { "classes" => @classes, "nil_count" => @nil_count, "samples" => @samples }
        omitted = @count - @samples.size
        # Present only when something was actually cut, so a reader
        # can trust its absence -- the same rule capture.rb applies to
        # frames_omitted and frame_source.rb applies to
        # locals_omitted.
        h["samples_omitted"] = omitted if omitted.positive?
        h
      end

      # Folds another Bucket's tally into this one. This is the
      # finish-time merge step for thread-local aggregation: each
      # thread records into its own Bucket with no lock, and totals
      # are combined once, in one place, instead of every call taking
      # a Mutex to update a single shared Bucket.
      #
      # Samples are re-capped at @max_samples here too: each
      # thread-local Bucket already capped its own samples
      # independently, so without this cap a target hit by N threads
      # could publish up to N * max_samples samples, silently
      # widening the documented limit just because more than one
      # thread happened to record some of the calls.
      def merge!(other)
        @count += other.count
        other.classes.each { |klass, n| @classes[klass] += n }
        @nil_count += other.nil_count
        other.samples.each do |sample|
          break if @samples.size >= @max_samples

          @samples << sample
        end
      end

      protected

      attr_reader :count, :classes, :nil_count, :samples

      private

      # Redaction gates on the parameter *name*, decided once at
      # Bucket construction, never on the value: this bucket's caller
      # (MethodStats) already checked the name against redact_patterns
      # before a single value was ever inspected, matching Redactor's
      # own rule of checking the name before touching the value.
      def sample_for(value)
        return { "redacted" => true, "reason" => "name" } if @redacted_name

        @formatter.format(value)
      end

      def safe_class_name(value)
        klass = value.class
        klass.respond_to?(:name) ? (klass.name || klass.to_s) : klass.to_s
      rescue Exception # rubocop:disable Lint/RescueException
        "Object"
      end
    end
  end
end
