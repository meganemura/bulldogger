# frozen_string_literal: true

require "json"

module Bulldogger
  # Parses and validates targets for verbs that re-execute application frames.
  # Collector launch and evidence writing stay in each verb.
  module ExecutionTarget
    FID_PATTERN = /\A(.+):([^:#]+)#([1-9]\d*)\z/
    Target = Data.define(:path, :method, :index, :root) do
      def application_path?(verb, stderr)
        return true if path.start_with?("#{root}/") && !path.start_with?("#{root}/vendor/bundle/")

        stderr.puts "bulldogger #{verb}: target is not an application frame; use the frames index, read the gem source, or use probe"
        false
      end
    end

    module_function

    def parse(fid, verb)
      match = FID_PATTERN.match(fid)
      raise ArgumentError, "#{verb} requires a fid in path:method#k form" unless match

      root = File.expand_path(Dir.pwd)
      Target.new(path: File.expand_path(match[1], root), method: match[2], index: Integer(match[3], 10), root: root)
    end

    def acceptable?(target, index:, code_state:, verb:, stderr:)
      return false unless target.application_path?(verb, stderr)

      index_state_matches?(index, code_state, verb, stderr)
    end

    def index_state_matches?(index, current, verb, stderr)
      return true unless index

      envelope = File.foreach(index).filter_map do |line|
        record = JSON.parse(line)
        record if record["type"] == "envelope"
      end.last
      indexed = envelope && envelope["code_state"]
      return true if indexed == current

      stderr.puts "bulldogger #{verb}: code state mismatch"
      stderr.puts "index git_sha=#{indexed&.fetch('git_sha', nil).inspect} dirty_digest=#{indexed&.fetch('dirty_digest', nil).inspect}"
      stderr.puts "run git_sha=#{current['git_sha'].inspect} dirty_digest=#{current['dirty_digest'].inspect}"
      false
    rescue Errno::ENOENT, JSON::ParserError
      stderr.puts "bulldogger #{verb}: cannot read index #{index}"
      false
    end
    private_class_method :index_state_matches?
  end
end
