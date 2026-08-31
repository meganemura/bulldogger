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
      raise ArgumentError, "#{verb} requires a fid in 'path:method#k' form" unless match

      root = File.expand_path(Dir.pwd)
      Target.new(path: File.expand_path(match[1], root), method: match[2], index: Integer(match[3], 10), root: root)
    end

    def acceptable?(target, index:, code_state:, verb:, stderr:, fid:)
      return false unless target.application_path?(verb, stderr)
      return false unless index_state_matches?(index, code_state, verb, stderr)

      addressable?(fid, index, verb, stderr)
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

    # flt/exec's own collectors gate on :call/:return only (a block has
    # no Method object to resolve a targeted TracePoint against), so a
    # block fid would silently produce an empty trace instead of
    # failing. The index's "event" field catches this even when the fid
    # text looks like an ordinary call -- a block nested in a def keeps
    # its enclosing method's name (e.g. "branchy#2"), indistinguishable
    # from a real call by pattern alone. Skipped without --index: there
    # is no data source to tell a block from a call in that case, so a
    # block fid run without an index still runs silently, as before.
    def addressable?(fid, index, verb, stderr)
      return true unless index

      record = frame_record(index, fid)
      return true unless record
      return true unless record["event"] == "b_call"

      ancestor = nearest_application_call(index, record)
      stderr.puts "bulldogger #{verb}: '#{fid}' is a block frame; #{verb} cannot target a block directly"
      if ancestor
        stderr.puts "target its nearest addressable ancestor instead: '#{ancestor}'"
      else
        stderr.puts "no addressable ancestor was recorded for it; use probe instead"
      end
      false
    rescue Errno::ENOENT, JSON::ParserError
      true # index_state_matches? already reported an unreadable index
    end
    private_class_method :addressable?

    def frame_record(index, fid)
      File.foreach(index) do |line|
        record = JSON.parse(line)
        return record if record["type"] == "frame" && record["fid"] == fid
      end
      nil
    end
    private_class_method :frame_record

    # Walks the parent chain from a block frame to the nearest ancestor
    # that application_path? would also accept: a call event (not a
    # block) inside the application, not a gem or framework frame.
    def nearest_application_call(index, record)
      current = record
      loop do
        parent_fid = current["parent"]
        return nil unless parent_fid

        parent_record = frame_record(index, parent_fid)
        return parent_fid unless parent_record
        return parent_fid if parent_record["event"] == "call" && parent_record["app"]

        current = parent_record
      end
    end
    private_class_method :nearest_application_call
  end
end
