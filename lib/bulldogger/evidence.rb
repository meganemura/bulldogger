# frozen_string_literal: true

require "json"
require_relative "version"
require_relative "skill"

module Bulldogger
  # Writes stored failure data and links valid replay evidence.
  # Capture and Replay own runtime observation; this class does not observe it.
  #
  # The exception's message and backtrace are read here, at report
  # time, not inside the :raise hook. Exception#backtrace can still be
  # nil when :raise fires -- Ruby fills it in as the exception
  # unwinds -- so reading it from the hook would record less than what
  # a test framework's own failure report already has by the time it
  # calls record_failure.
  class Evidence
    SLUG_MAX_LENGTH = 80

    def initialize(config:, run:, capture:, replay: nil, code_state: CodeState.capture)
      @config = config
      @run = run
      @capture = capture
      @replay = replay
      @code_state = code_state
    end

    def record_failure(exception:, test:)
      # A disabled switch means "wrote nothing" -- not "wrote an empty
      # missed record". Writing capture_mode: missed here would mean
      # a user who turned this off still gets a run directory and a
      # frames_unavailable_reason, which reads as "tried and failed"
      # rather than "did not run", the opposite of what they asked for.
      return nil unless @config.enabled
      return nil if exception.nil?

      path = @run.next_path(slug_for(test))
      payload = build_payload(exception: exception, test: test)
      result = @replay&.call(test: test, run_dir: File.dirname(path), frames: payload["frames"])
      attach_replay(payload, result)
      File.write(path, "#{JSON.pretty_generate(payload)}\n")
      @run.record(path, test: payload["test"], exception_summary: payload["exception"].slice("class", "message"))
      path
    end

    private

    def attach_replay(payload, result)
      return unless result

      # A broken path costs a reader more than a missing key. Replay and skill
      # paths must resolve to files, so replay names only an existing trace.
      #
      # A false value means the failure passed in isolation. This signal can
      # reveal order dependence or shared state, so silence would lose evidence.
      payload["replay"] = result[:path] if result[:path] && File.file?(result[:path])
      payload["replay_reproduced"] = result[:reproduced] if result.key?(:reproduced)
      payload["replay_skipped_reason"] = result[:skipped_reason] if result[:skipped_reason]
    end

    def build_payload(exception:, test:)
      snapshot = @capture.snapshot_for(exception)
      payload = {
        # Readers can ignore the added skill key, so the compatible schema
        # change keeps version 1.
        "schema_version" => 1,
        "tool" => { "name" => "bulldogger", "version" => Bulldogger::VERSION },
        "captured_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "capture_mode" => snapshot ? snapshot["capture_mode"] : "missed",
        "seed" => test && test[:seed],
        "rerun_command" => RerunCommand.build(test),
        "raise_ordinal" => snapshot && snapshot["raise_ordinal"],
        "code_state" => @code_state,
        "test" => normalize_test(test),
        "exception" => build_exception_section(exception),
        "frames" => snapshot ? snapshot["frames"] : []
      }
      # The failure output must lead an agent to the skill at the moment of
      # need. The evidence path alone gives no route to those instructions.
      skill_file = Bulldogger::Skill.file
      payload["skill"] = skill_file if skill_file
      frames_omitted = snapshot ? snapshot["frames_omitted"] : 0
      payload["frames_omitted"] = frames_omitted if frames_omitted&.positive?
      payload["frames_unavailable_reason"] = @capture.reason_for_missing(exception) unless snapshot
      payload["limits"] = limits_section
      payload
    end

    def build_exception_section(exception)
      message = exception.message.to_s
      limit = @config.max_value_length * 5
      section = {
        "class" => exception_class_name(exception),
        "message" => message.length > limit ? "#{message[0, limit]}…" : message
      }
      if message.length > limit
        section["message_truncated"] = true
        section["message_original_length"] = message.length
      end
      section["backtrace"] = Array(exception.backtrace).first(@config.max_frames)
      section
    end

    def exception_class_name(exception)
      exception.class.name || exception.class.to_s
    rescue Exception # rubocop:disable Lint/RescueException
      "Object"
    end

    def normalize_test(test)
      test ||= {}
      {
        "framework" => test[:framework],
        "id" => test[:id],
        "file" => test[:file],
        "line" => test[:line]
      }
    end

    def limits_section
      {
        "max_frames" => @config.max_frames,
        "max_locals" => @config.max_locals,
        "max_value_length" => @config.max_value_length
      }
    end

    def slug_for(test)
      raw = (test && test[:id] || "unknown").to_s
      raw.gsub(/[^A-Za-z0-9_-]/, "-")[0, SLUG_MAX_LENGTH]
    end
  end
end
