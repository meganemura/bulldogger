# frozen_string_literal: true

require "json"
require_relative "../skill"

module Bulldogger
  module Probe
    # Writes one probe session's aggregated MethodStats as
    # tmp/bulldogger/run-.../probe-NNN-<slug>.json.
    #
    # Filenames use their own "probe-NNN-" sequence, not Run#next_path
    # (which produces plain "NNN-<slug>.json" for failure evidence):
    # Run is owned by the base-snapshot task and not touched here, and
    # its sequence and this one are independent counters that happen
    # to share a directory, not a single numbering space. Run#dir is
    # still used for the lazy, on-first-write mkdir: probe is an
    # explicit verb (AGENTS.md), so unlike a green test suite, a
    # session that finished is itself the request to write, and does
    # so even if it observed zero calls.
    module Writer
      @sequence = 0
      @mutex = Mutex.new

      class << self
        attr_accessor :sequence
        attr_reader :mutex
      end

      def self.write(run:, config:, targets:, stats:, started_at:)
        dir = run.dir
        return nil unless dir

        path = File.join(dir, format("probe-%03d-%s.json", next_sequence, slug_for(targets)))
        File.write(path, "#{JSON.pretty_generate(payload_for(config: config, targets: targets, stats: stats,
                                                              started_at: started_at))}\n")
        path
      end

      def self.next_sequence
        mutex.synchronize { self.sequence += 1 }
      end

      def self.slug_for(targets)
        raw = targets.map(&:label).join("_")
        raw.gsub(/[^A-Za-z0-9_-]/, "-")[0, 80]
      end

      def self.payload_for(config:, targets:, stats:, started_at:)
        payload = {
          "schema_version" => 1,
          "kind" => "probe",
          "tool" => { "name" => "bulldogger", "version" => Bulldogger::VERSION },
          "started_at" => started_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
          "targets" => targets.map(&:label),
          "methods" => targets.each_with_object({}) { |t, h| h[t.label] = stats[t.label].to_h },
          "limits" => { "max_samples" => config.max_samples, "max_value_length" => config.max_value_length }
        }
        skill_file = Bulldogger::Skill.file
        payload["skill"] = skill_file if skill_file
        payload
      end
      private_class_method :next_sequence, :slug_for, :payload_for
    end
  end
end
