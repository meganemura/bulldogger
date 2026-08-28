# frozen_string_literal: true

require "json"
require_relative "version"

module Bulldogger
  # Assembles and writes one evidence file: the exception, the test it
  # failed in, and (if the ring still has it) the snapshot captured at
  # :raise time.
  #
  # The exception's message and backtrace are read here, at report
  # time, not inside the :raise hook. Exception#backtrace can still be
  # nil when :raise fires -- Ruby fills it in as the exception
  # unwinds -- so reading it from the hook would record less than what
  # a test framework's own failure report already has by the time it
  # calls record_failure.
  class Evidence
    SLUG_MAX_LENGTH = 80

    def initialize(config:, run:, capture:)
      @config = config
      @run = run
      @capture = capture
    end

    def record_failure(exception:, test:)
      return nil if exception.nil?

      path = @run.next_path(slug_for(test))
      payload = build_payload(exception: exception, test: test)
      File.write(path, "#{JSON.pretty_generate(payload)}\n")
      @run.record(path, test: payload["test"], exception_summary: payload["exception"].slice("class", "message"))
      path
    end

    private

    def build_payload(exception:, test:)
      snapshot = @capture.snapshot_for(exception)
      payload = {
        "schema_version" => 1,
        "tool" => { "name" => "bulldogger", "version" => Bulldogger::VERSION },
        "captured_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "capture_mode" => snapshot ? snapshot["capture_mode"] : "missed",
        "test" => normalize_test(test),
        "exception" => build_exception_section(exception),
        "frames" => snapshot ? snapshot["frames"] : []
      }
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
