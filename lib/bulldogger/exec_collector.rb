# frozen_string_literal: true

# Each inferred test-environment signal produced one false positive and one false negative.
# Only an explicit launch token can authorize statement evaluation.
if ENV["BULLDOGGER_EXEC"] == "1" && ENV["BULLDOGGER_EXEC_OUT"] && ENV["BULLDOGGER_EXEC_FID"]
  require "json"
  require_relative "config"
  require_relative "formatter"
  require_relative "frames_collector"
  require_relative "redactor"

  module Bulldogger
    # Evaluates one statement at an addressed line visit inside a test window.
    # The launcher owns target validation, process outcome, and the envelope.
    module ExecCollector
      class << self
        def begin_test
          @active = true
          @count = 0
        end

        def end_test
          @line_trace&.disable
          @line_trace = nil
          @active = false
        end

        private

        def dispatch(trace)
          return unless @active
          return unless File.expand_path(trace.path) == @target_path
          return unless FramesMethod.normalize(trace.method_id) == @target_method

          if trace.event == :call
            enter(trace)
          else
            leave
          end
        rescue StandardError
          nil
        end

        def enter(trace)
          if @line_trace
            @target_depth += 1
            return
          end

          @count += 1
          return unless @count == @target_index

          @visits = 0
          @target_depth = 1
          iseq = RubyVM::InstructionSequence.of(trace.binding.eval("method(__method__)"))
          @line_trace = TracePoint.new(:line) { |event| evaluate(event) }
          @line_trace.enable(target: iseq)
        end

        def leave
          return unless @line_trace

          @target_depth -= 1
          return unless @target_depth.zero?

          @line_trace.disable
          @line_trace = nil
        end

        def evaluate(trace)
          return unless trace.lineno == @target_line

          @visits += 1
          return unless @visits == @target_visit

          begin
            value = trace.binding.eval(@statement)
            write("type" => "evaluation", "fid" => @fid, "line" => @target_line, "visit" => @target_visit, "value" => @formatter.format(value))
          rescue Exception => error # rubocop:disable Lint/RescueException
            write("type" => "evaluation", "fid" => @fid, "line" => @target_line, "visit" => @target_visit, "exception_class" => error.class.name, "message" => @formatter.format(error.message))
          ensure
            @line_trace.disable
            @line_trace = nil
            @target_depth = 0
          end
        end

        def write(record)
          @mutex.synchronize do
            @file.puts JSON.generate(record)
            @file.flush
          end
        end
      end

      @fid = ENV.fetch("BULLDOGGER_EXEC_FID")
      match = /\A(.+):([^:#]+)#([1-9]\d*)\z/.match(@fid)
      @target_path = File.expand_path(match[1])
      @target_method = match[2]
      @target_index = Integer(match[3], 10)
      @target_line = Integer(ENV.fetch("BULLDOGGER_EXEC_LINE"), 10)
      @target_visit = Integer(ENV.fetch("BULLDOGGER_EXEC_VISIT"), 10)
      @statement = ENV.fetch("BULLDOGGER_EXEC_STATEMENT")
      config = Config.new
      redactor = Redactor.new(config.redact_patterns)
      @formatter = Formatter.new(config: config, redactor: redactor)
      @active = false
      @count = 0
      @target_depth = 0
      @mutex = Mutex.new
      @file = File.open("#{ENV.fetch('BULLDOGGER_EXEC_OUT')}-#{Process.pid}.jsonl", "a")
      # This gate stays active for the full run, so each extra event adds pass-through cost.
      @gate = TracePoint.new(:call, :return) { |trace| dispatch(trace) }
      @gate.enable
      at_exit do
        @line_trace&.disable
        @gate.disable
        @file.close
      end
    end
  end
end
