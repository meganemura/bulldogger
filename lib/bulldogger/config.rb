# frozen_string_literal: true
# rbs_inline: enabled

module Bulldogger
  # Sets bounded runtime policy for capture, redaction, and file output.
  # It does not start capture work.
  # Environment overrides let a child change policy without app file changes.
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
    ].freeze #: Array[Regexp]

    attr_accessor :enabled #: bool
    attr_accessor :output_dir #: String
    attr_accessor :max_frames #: Integer
    attr_accessor :max_locals #: Integer
    attr_accessor :max_value_length #: Integer
    attr_accessor :max_pending #: Integer
    attr_accessor :max_samples #: Integer
    attr_accessor :redact_patterns #: Array[Regexp | String]
    # :auto, :capture_frames or :degraded
    attr_accessor :frame_source #: Symbol

    #: () -> void
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
      apply_env_overrides
    end

    private

    #: () -> void
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
    end
  end
end
