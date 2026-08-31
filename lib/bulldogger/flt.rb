# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "code_state"
require_relative "frames"

module Bulldogger
  module Flt
    SCHEMA_VERSION = 1
    FID_PATTERN = /\A(.+):([^:#]+)#([1-9]\d*)\z/

    module_function

    def run(fid, command, index: nil, output_dir: ENV.fetch("BULLDOGGER_OUTPUT_DIR", "tmp/bulldogger"), stdout: $stdout, stderr: $stderr)
      match = FID_PATTERN.match(fid)
      raise ArgumentError, "flt requires a fid in path:method#k form" unless match
      raise ArgumentError, "flt requires a command after --" if command.empty?

      root = File.expand_path(Dir.pwd)
      target_path = File.expand_path(match[1], root)
      unless application_path?(target_path, root)
        stderr.puts "bulldogger flt: target is not an application frame; use the frames index, read the gem source, or use probe"
        return 1
      end

      code_state = CodeState.capture(root)
      return 1 unless index_state_matches?(index, code_state, stderr)

      output_dir = File.expand_path(output_dir)
      FileUtils.mkdir_p(output_dir)
      base_path = File.join(output_dir, "flt")
      collector = File.expand_path("flt_collector.rb", __dir__)
      env = collector_environment(base_path, collector, "#{target_path}:#{match[2]}##{match[3]}")
      pid = Process.spawn(env, *command)
      _waited_pid, status = Process.wait2(pid)
      path = "#{base_path}-#{pid}.jsonl"
      File.open(path, "a") do |file|
        file.puts JSON.generate(
          "type" => "envelope", "schema_version" => SCHEMA_VERSION,
          "code_state" => code_state, "command" => command, "exit_status" => status.exitstatus
        )
      end
      stdout.puts "bulldogger flt: #{path}"
      stdout.puts "bulldogger result: #{Frames.send(:outcome, status)} (exit #{status.exitstatus || status.termsig})"
      status
    end

    def application_path?(path, root)
      path.start_with?("#{root}/") && !path.start_with?("#{root}/vendor/bundle/")
    end
    private_class_method :application_path?

    def index_state_matches?(index, current, stderr)
      return true unless index

      envelope = File.foreach(index).filter_map do |line|
        record = JSON.parse(line)
        record if record["type"] == "envelope"
      end.last
      indexed = envelope && envelope["code_state"]
      return true if indexed == current

      stderr.puts "bulldogger flt: code state mismatch"
      stderr.puts "index git_sha=#{indexed&.fetch('git_sha', nil).inspect} dirty_digest=#{indexed&.fetch('dirty_digest', nil).inspect}"
      stderr.puts "run git_sha=#{current['git_sha'].inspect} dirty_digest=#{current['dirty_digest'].inspect}"
      false
    rescue Errno::ENOENT, JSON::ParserError
      stderr.puts "bulldogger flt: cannot read index #{index}"
      false
    end
    private_class_method :index_state_matches?

    def collector_environment(base_path, collector, fid)
      option = "-r#{collector}"
      rubyopt = ENV["RUBYOPT"]
      {
        "BULLDOGGER_FLT_OUT" => base_path,
        "BULLDOGGER_FLT_FID" => fid,
        "RUBYOPT" => rubyopt.nil? || rubyopt.empty? ? option : "#{rubyopt} #{option}"
      }
    end
    private_class_method :collector_environment
  end
end
