# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "code_state"
require_relative "collector_environment"
require_relative "execution_target"
require_relative "frames"

module Bulldogger
  module Flt
    SCHEMA_VERSION = 1
    module_function

    def run(fid, command, index: nil, output_dir: ENV.fetch("BULLDOGGER_OUTPUT_DIR", "tmp/bulldogger"), stdout: $stdout, stderr: $stderr)
      target = ExecutionTarget.parse(fid, "flt")
      raise ArgumentError, "flt requires a command after --" if command.empty?

      code_state = CodeState.capture(target.root)
      return 1 unless ExecutionTarget.acceptable?(target, index: index, code_state: code_state, verb: "flt", stderr: stderr)

      output_dir = File.expand_path(output_dir)
      FileUtils.mkdir_p(output_dir)
      base_path = File.join(output_dir, "flt")
      env = CollectorEnvironment.build("flt_collector.rb", "BULLDOGGER_FLT_OUT" => base_path, "BULLDOGGER_FLT_FID" => fid)
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

  end
end
