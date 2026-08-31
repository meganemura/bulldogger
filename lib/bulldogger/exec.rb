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
      return 1 unless ExecutionTarget.acceptable?(target, index: index, code_state: code_state, verb: "exec", stderr: stderr, fid: fid)

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
      summary = records.reverse.find { |record| record["type"] == "target_summary" }
      visit_summary = records.reverse.find { |record| record["type"] == "evaluation_summary" }
      result = {
        "type" => "result", "fid" => fid, "line" => line, "visit" => visit,
        "outcome" => outcome, "exit_status" => status.exitstatus
      }
      result.merge!(evaluation.reject { |key, _value| key == "type" }) if evaluation
      envelope = { "type" => "envelope", "schema_version" => SCHEMA_VERSION, "code_state" => code_state, "command" => command }
      if summary
        envelope["observed_calls"] = summary["observed_calls"]
        envelope["target_index"] = summary["target_index"]
        envelope["traced"] = false
      elsif visit_summary
        envelope["line_visits_observed"] = visit_summary["line_visits_observed"]
        envelope["target_visit"] = visit_summary["target_visit"]
        envelope["evaluated"] = false
      end
      File.open(path, "a") do |file|
        file.puts JSON.generate(result)
        file.puts JSON.generate(envelope)
      end
      stdout.puts "bulldogger exec: #{path}"
      stdout.puts "bulldogger note: #{never_traced_note(summary)}" if summary
      stdout.puts "bulldogger note: #{never_evaluated_note(fid, visit_summary)}" if visit_summary
      stdout.puts "bulldogger value: #{result.dig('value', 'value')}" if result["value"]
      stdout.puts "bulldogger result: #{outcome} (exit #{status.exitstatus || status.termsig})"
      status
    end

    def never_traced_note(summary)
      calls = summary.fetch("observed_calls")
      "target was never traced (method called #{calls} #{calls == 1 ? 'time' : 'times'} in the test window, target was call ##{summary.fetch('target_index')})"
    end
    private_class_method :never_traced_note

    def never_evaluated_note(fid, summary)
      visits = summary.fetch("line_visits_observed")
      call_index = fid[/#(\d+)\z/, 1]
      "statement was never evaluated (line #{summary.fetch('line')} visited #{visits} #{visits == 1 ? 'time' : 'times'} " \
        "in call ##{call_index}, target was visit ##{summary.fetch('target_visit')})"
    end
    private_class_method :never_evaluated_note

  end
end
