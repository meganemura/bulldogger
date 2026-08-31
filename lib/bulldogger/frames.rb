# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "code_state"

module Bulldogger
  # Runs one command with structural frame collection enabled.
  # It does not select tests or change command arguments.
  module Frames
    SCHEMA_VERSION = 1

    module_function

    def run(command, output_dir: ENV.fetch("BULLDOGGER_OUTPUT_DIR", "tmp/bulldogger"), stdout: $stdout)
      raise ArgumentError, "frames requires a command after --" if command.empty?

      output_dir = File.expand_path(output_dir)
      FileUtils.mkdir_p(output_dir)
      base_path = File.join(output_dir, "frames")
      collector = File.expand_path("frames_collector.rb", __dir__)
      env = collector_environment(base_path, collector)
      pid = Process.spawn(env, *command)
      _waited_pid, status = Process.wait2(pid)
      path = "#{base_path}-#{pid}.jsonl"
      append_envelope(path, command, status)
      stdout.puts "bulldogger frames: #{path}"
      stdout.puts "bulldogger result: #{outcome(status)} (exit #{status.exitstatus || status.termsig})"
      status
    end

    def collector_environment(base_path, collector)
      option = "-r#{collector}"
      rubyopt = ENV["RUBYOPT"]
      {
        "BULLDOGGER_FRAMES_OUT" => base_path,
        "RUBYOPT" => rubyopt.nil? || rubyopt.empty? ? option : "#{rubyopt} #{option}"
      }
    end
    private_class_method :collector_environment

    def append_envelope(path, command, status)
      summary = read_summary(path)
      envelope = {
        "type" => "envelope",
        "schema_version" => SCHEMA_VERSION,
        "code_state" => CodeState.capture,
        "seed" => seed_from(command),
        "command" => command,
        "exit_status" => status.exitstatus,
        "outside_window_events" => summary.fetch("outside_window_events", 0)
      }
      File.open(path, "a") { |file| file.puts(JSON.generate(envelope)) }
    end
    private_class_method :append_envelope

    def read_summary(path)
      return {} unless File.file?(path)

      File.foreach(path).filter_map do |line|
        record = JSON.parse(line)
        record if record["type"] == "summary"
      end.last || {}
    end
    private_class_method :read_summary

    def seed_from(command)
      index = command.index("--seed")
      return Integer(command[index + 1], 10) if index && command[index + 1]

      seed = command.find { |argument| argument.start_with?("--seed=") }
      seed && Integer(seed.delete_prefix("--seed="), 10)
    rescue ArgumentError
      nil
    end
    private_class_method :seed_from

    def outcome(status)
      return "pass" if status.success?
      return "error" if status.signaled?

      "fail"
    end
    private_class_method :outcome
  end
end
