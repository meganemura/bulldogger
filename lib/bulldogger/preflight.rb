# frozen_string_literal: true

require "json"
require "stringio"
require_relative "frames"

module Bulldogger
  # Compares application frames from two isolated command runs.
  # It does not select tests or change command arguments.
  module Preflight
    module_function

    def run(command, stdout: $stdout, stderr: $stderr)
      raise ArgumentError, "preflight requires a command after --" if command.empty?

      first_path = collect(command)
      second_path = collect(command)
      first_frames = application_frames(first_path)
      second_frames = application_frames(second_path)

      if first_frames == second_frames
        stdout.puts "bulldogger preflight: deterministic (app frames: #{first_frames.length})"
        stdout.puts "bulldogger preflight indexes: #{first_path} #{second_path}"
        return 0
      end

      divergence = first_divergence(first_frames, second_frames)
      stdout.puts "bulldogger preflight: first divergence at event #{divergence + 1}"
      stdout.puts "first: #{format_frame(first_frames[divergence])}"
      stdout.puts "second: #{format_frame(second_frames[divergence])}"
      stdout.puts "app frames: #{first_frames.length} and #{second_frames.length}"
      stdout.puts "This test is not eligible for bulldogger re-execution."
      1
    rescue SystemCallError, IOError, JSON::ParserError => error
      stderr.puts "bulldogger preflight: failed to start or collect the command: #{error.message}"
      2
    end

    def collect(command)
      report = StringIO.new
      Frames.run(command, stdout: report)
      path = report.string[/bulldogger frames: (.+\.jsonl)$/, 1]
      raise IOError, "the frames index path is unavailable" unless path && File.file?(path)
      raise IOError, "the command produced no frame summary" unless frame_summary?(path)

      path
    end
    private_class_method :collect

    def frame_summary?(path)
      File.foreach(path).any? { |line| JSON.parse(line)["type"] == "summary" }
    end
    private_class_method :frame_summary?

    def application_frames(path)
      File.foreach(path).filter_map do |line|
        record = JSON.parse(line)
        next unless record["type"] == "frame" && record["app"] == true

        [record["event"], record["path"], record["lineno"], record["method"]]
      end
    end
    private_class_method :application_frames

    def first_divergence(first_frames, second_frames)
      limit = [first_frames.length, second_frames.length].min
      (0...limit).find { |index| first_frames[index] != second_frames[index] } || limit
    end
    private_class_method :first_divergence

    def format_frame(frame)
      return "(end of sequence)" unless frame

      event, path, lineno, method_name = frame
      "(#{event}, #{path}:#{lineno}, #{method_name})"
    end
    private_class_method :format_frame
  end
end
