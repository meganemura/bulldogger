# frozen_string_literal: true

if ENV["BULLDOGGER_FLT_OUT"] && ENV["BULLDOGGER_FLT_FID"]
  require "json"
  require_relative "config"
  require_relative "formatter"
  require_relative "frames_collector"
  require_relative "redactor"

  module Bulldogger
    module FltCollector
      class << self
        def begin_test
          @active = true
          @count = 0
        end

        def end_test
          finish_trace
          @active = false
        end

        private

        def dispatch(trace)
          return unless @active
          return unless File.expand_path(trace.path) == @target_path
          return unless FramesMethod.normalize(trace.method_id) == @target_method

          trace.event == :call ? enter(trace) : leave(trace)
        rescue StandardError
          nil
        end

        def enter(trace)
          if @line_trace
            @target_depth += 1
            return
          end

          @count += 1
          @observed_calls = @count if @count > @observed_calls
          return unless @count == @target_index

          @target_reached = true
          @target_binding = trace.binding
          @target_depth = 1
          @previous = snapshot(trace.binding)
          write("type" => "call", "fid" => @fid, "args" => arguments(trace), "locals" => @previous)
          iseq = RubyVM::InstructionSequence.of(trace.binding.eval("method(__method__)"))
          @line_trace = TracePoint.new(:line, :raise) { |event| line_dispatch(event) }
          @line_trace.enable(target: iseq)
        end

        def leave(trace)
          return unless @line_trace

          @target_depth -= 1
          return unless @target_depth.zero?

          value = format_value("return", trace.return_value)
          finish_trace
          write("type" => "return", "value" => value)
        end

        def line_dispatch(trace)
          if trace.event == :raise
            error = trace.raised_exception
            write("type" => "raise", "exception_class" => error.class.name, "message" => format_value("message", error.message))
            return
          end

          current = snapshot(trace.binding)
          new_names = current.keys - @previous.keys
          removed = @previous.keys - current.keys
          changed_names = (current.keys & @previous.keys).select { |name| current[name] != @previous[name] }
          record = { "type" => "line", "lineno" => trace.lineno }
          record["new"] = current.slice(*new_names) unless new_names.empty?
          unless changed_names.empty?
            record["changed"] = changed_names.to_h { |name| [name, { "old" => @previous[name], "new" => current[name] }] }
          end
          # Differential changes cannot reconstruct visible state after a block-local leaves scope.
          record["out_of_scope"] = removed unless removed.empty?
          fold(record)
          @previous = current
        end

        def fold(record)
          line = record.fetch("lineno")
          flush_loop while @loops&.any? && (line > @loops.last[:end] || line < @loops.last[:start])
          if @loops&.any? && @last_line && line <= @last_line
            loop = @loops.last
            if line <= loop[:start]
              loop[:skipped] += 1
              loop[:buffer] = [record]
            else
              @loops << { start: line, end: @last_line, skipped: 0, buffer: [record] }
            end
          elsif @last_line && line <= @last_line
            @loops ||= []
            @loops << { start: line, end: @last_line, skipped: 0, buffer: [record] }
          else
            emit_folded(record)
          end
          @last_line = line
        end

        def flush_loop
          loop = @loops&.pop
          return unless loop

          emit_folded("type" => "skipped_iterations", "count" => loop[:skipped]) if loop[:skipped].positive?
          loop[:buffer].each { |record| emit_folded(record) }
        end

        def emit_folded(record)
          if @loops&.any?
            @loops.last[:buffer] << record
          else
            write(record)
          end
        end

        def snapshot(binding)
          binding.local_variables.to_h do |name|
            string = name.to_s
            value = @redactor.redact_name?(string) ? { "value" => "[REDACTED]" } : @formatter.format(binding.local_variable_get(name))
            [string, value]
          end
        end

        def arguments(trace)
          method_object = trace.binding.eval("method(__method__)")
          method_object.parameters.filter_map do |_kind, name|
            next unless name && @previous.key?(name.to_s)
            [name.to_s, @previous[name.to_s]]
          end.to_h
        end

        def format_value(name, value)
          @redactor.redact_name?(name) ? { "value" => "[REDACTED]" } : @formatter.format(value)
        end

        def finish_trace
          flush_loop while @loops&.any?
          @line_trace&.disable
          @line_trace = nil
          @target_binding = nil
          @target_depth = 0
          @last_line = nil
        end

        def write(record)
          @mutex.synchronize do
            @file.puts JSON.generate(record)
            @file.flush
          end
        end
      end

      @fid = ENV.fetch("BULLDOGGER_FLT_FID")
      match = /\A(.+):([^:#]+)#([1-9]\d*)\z/.match(@fid)
      @target_path = File.expand_path(match[1])
      @target_method = match[2]
      @target_index = Integer(match[3], 10)
      config = Config.new
      @redactor = Redactor.new(config.redact_patterns)
      @formatter = Formatter.new(config: config, redactor: @redactor)
      @active = false
      @count = 0
      @observed_calls = 0
      @target_reached = false
      @mutex = Mutex.new
      @file = File.open("#{ENV.fetch('BULLDOGGER_FLT_OUT')}-#{Process.pid}.jsonl", "a")
      # This gate stays active for the full run, so each extra event adds pass-through cost.
      @gate = TracePoint.new(:call, :return) { |trace| dispatch(trace) }
      @gate.enable
      at_exit do
        write("type" => "target_summary", "observed_calls" => @observed_calls, "target_index" => @target_index, "traced" => false) unless @target_reached
        @line_trace&.disable
        @gate.disable
        @file.close
      end
    end
  end
end
