# frozen_string_literal: true

module Bulldogger
  # Runtime knobs for capture, redaction, and file output. Each attribute
  # has a hard-coded default so the tool works with zero setup; the
  # environment variable overrides exist so an agent running tests in a
  # child process can change behavior (for example, pointing output_dir
  # at a scratch directory) without editing the app's own config file.
  class Config
    DEFAULT_REDACT_PATTERNS = [
      /pass(?:word|wd)?/i,
      /secret/i,
      /token/i,
      /api[_-]?key/i,
      /\bkey\b/i,
      /credential/i,
      /auth/i,
      /session/i,
      /cookie/i
    ].freeze

    attr_accessor :enabled, :output_dir, :max_frames, :max_locals,
                   :max_value_length, :max_pending, :max_samples, :redact_patterns,
                   :frame_source, :replay_on_failure, :max_replays, :replay_timeout

    def initialize
      @enabled = true
      @output_dir = "tmp/bulldogger"
      @max_frames = 20
      @max_locals = 50
      @max_value_length = 200
      @max_pending = 32
      @max_samples = 10
      @redact_patterns = DEFAULT_REDACT_PATTERNS.dup
      @frame_source = :auto
      @replay_on_failure = true
      @max_replays = 1
      @replay_timeout = 60
      apply_env_overrides
    end

    private

    def apply_env_overrides
      output_dir_override = ENV["BULLDOGGER_OUTPUT_DIR"]
      @output_dir = output_dir_override if output_dir_override && !output_dir_override.empty?

      case ENV["BULLDOGGER_FRAME_SOURCE"]
      when "capture_frames" then @frame_source = :capture_frames
      when "degraded" then @frame_source = :degraded
      end

      # BULLDOGGER_DISABLE is the documented name; BULLDOGGER_DISABLED is
      # accepted too. An adjective is the form English speakers reach
      # for first, and a kill switch that silently ignores the natural
      # spelling is worse than one that accepts an extra name.
      @enabled = false if ENV["BULLDOGGER_DISABLE"] == "1" || ENV["BULLDOGGER_DISABLED"] == "1"
      @replay_on_failure = false if ENV["BULLDOGGER_REPLAY"] == "0"
      @max_replays = Integer(ENV["BULLDOGGER_MAX_REPLAYS"], 10) if ENV["BULLDOGGER_MAX_REPLAYS"]
    rescue ArgumentError
      @max_replays = 1
    end
  end
end
