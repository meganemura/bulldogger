# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "code_state"
require_relative "collector_environment"
require_relative "execution_target"
require_relative "frames"

module Bulldogger
  # Runs one command with one addressed statement injection.
  # The collector owns frame selection and statement evaluation.
  module Exec
    SCHEMA_VERSION = 1

    module_function

    def run(fid, command, line:, statement:, visit: 1, index: nil, output_dir: ENV.fetch("BULLDOGGER_OUTPUT_DIR", "tmp/bulldogger"), stdout: $stdout, stderr: $stderr)
      target = ExecutionTarget.parse(fid, "exec")
      raise ArgumentError, "exec requires a command after --" if command.empty?
      raise ArgumentError, "exec requires a positive line" unless line.positive?
      raise ArgumentError, "exec requires a positive visit" unless visit.positive?

      code_state = CodeState.capture(target.root)
      return 1 unless ExecutionTarget.acceptable?(target, index: index, code_state: code_state, verb: "exec", stderr: stderr)

      output_dir = File.expand_path(output_dir)
      FileUtils.mkdir_p(output_dir)
      base_path = File.join(output_dir, "exec")
      env = CollectorEnvironment.build(
        "exec_collector.rb",
        "BULLDOGGER_EXEC" => "1", "BULLDOGGER_EXEC_OUT" => base_path,
        "BULLDOGGER_EXEC_FID" => fid, "BULLDOGGER_EXEC_LINE" => line.to_s,
        "BULLDOGGER_EXEC_VISIT" => visit.to_s, "BULLDOGGER_EXEC_STATEMENT" => statement
      )
      pid = Process.spawn(env, *command)
      _waited_pid, status = Process.wait2(pid)
      path = "#{base_path}-#{pid}.jsonl"
      outcome = Frames.send(:outcome, status)
      records = File.file?(path) ? File.readlines(path, chomp: true).map { |entry| JSON.parse(entry) } : []
      evaluation = records.reverse.find { |record| record["type"] == "evaluation" }
      result = {
        "type" => "result", "fid" => fid, "line" => line, "visit" => visit,
        "outcome" => outcome, "exit_status" => status.exitstatus
      }
      result.merge!(evaluation.reject { |key, _value| key == "type" }) if evaluation
      File.open(path, "a") do |file|
        file.puts JSON.generate(result)
        file.puts JSON.generate("type" => "envelope", "schema_version" => SCHEMA_VERSION, "code_state" => code_state, "command" => command)
      end
      stdout.puts "bulldogger exec: #{path}"
      stdout.puts "bulldogger value: #{result.dig('value', 'value')}" if result["value"]
      stdout.puts "bulldogger result: #{outcome} (exit #{status.exitstatus || status.termsig})"
      status
    end

  end
end
