# frozen_string_literal: true

require "json"
require_relative "application_frames"

module Bulldogger
  # Formats the file guidance that the recorded evidence state supports.
  # Integrations own framework output; this module only formats two stable lines.
  module FailureOutput
    module_function

    def lines(path, replay_enabled: true)
      evidence = JSON.parse(File.read(path))
      replay_path = evidence["replay"]

      if evidence["capture_mode"] == "missed"
        ["bulldogger evidence: #{path} (snapshot holds no frames)"]
      elsif replay_path
        ["bulldogger evidence: #{path}", replay_guidance(replay_path, evidence["replay_reproduced"])]
      elsif ApplicationFrames.available?(evidence.dig("test", "file"), evidence.fetch("frames", []))
        ["bulldogger evidence: #{path} (raising method is in these frames)"]
      else
        [missing_origin_line(path, replay_enabled)]
      end
    rescue JSON::ParserError, SystemCallError
      ["bulldogger evidence: #{path}"]
    end

    def replay_guidance(path, reproduced)
      reason = if reproduced == false
                 "test passed alone; this trace shows the passing run"
               else
                 "value was produced before the assertion raised"
               end
      "bulldogger replay: #{path} (#{reason})"
    end

    def missing_origin_line(path, replay_enabled)
      reason = "frames do not show where the value came from"
      reason += "; set BULLDOGGER_REPLAY=1" unless replay_enabled
      "bulldogger evidence: #{path} (#{reason})"
    end
  end
end
