# frozen_string_literal: true

require "json"
require_relative "application_frames"

module Bulldogger
  # Formats the file guidance that the recorded evidence state supports.
  # Integrations own framework output; this module only formats two stable lines.
  module FailureOutput
    module_function

    def lines(path)
      evidence = JSON.parse(File.read(path))

      lines = if evidence["capture_mode"] == "missed"
        ["bulldogger evidence: #{path} (snapshot holds no frames)"]
      elsif ApplicationFrames.available?(evidence.dig("test", "file"), evidence.fetch("frames", []))
        ["bulldogger evidence: #{path} (raising method is in these frames)"]
      else
        [missing_origin_line(path)]
      end
      lines << "bulldogger rerun: #{evidence['rerun_command']}" if evidence["rerun_command"]
      lines
    rescue JSON::ParserError, SystemCallError
      ["bulldogger evidence: #{path}"]
    end

    def missing_origin_line(path)
      "bulldogger evidence: #{path} (frames do not show where the value came from)"
    end
  end
end
