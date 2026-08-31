# frozen_string_literal: true

module Bulldogger
  module FramesMethod
    module_function

    # CRuby seeds String#hash per process, and compiled template method names embed it.
    # Folding numeric segments keeps frame identities stable across isolated runs.
    def normalize(method_id)
      method_id.to_s.gsub(/_{2,3}-?\d{6,}_\d+/, "__HASH__")
    end
  end
end

if ENV["BULLDOGGER_FRAMES_OUT"] && !ENV["BULLDOGGER_FRAMES_OUT"].empty?
  require "json"

  module Bulldogger
    # Streams structural events for test windows in the current process.
    # It does not capture values or control test execution.
    module FramesCollector
      EVENTS = %i[call b_call return b_return raise].freeze
      COLLECTOR_DIR = File.expand_path(__dir__)

      class << self
        def begin_test
          @active = true
          @raise_ordinal = 0
          @counts = Hash.new(0)
          @stack = []
        end

        def end_test
          @active = false
          @stack = []
        end

        def active?
          @active == true
        end

        private

        def record(trace)
          if active?
            record_window_event(trace)
          else
            @outside_window_events += 1
          end
        rescue StandardError
          nil
        end

        def record_window_event(trace)
          raw_path = trace.path
          path = raw_path.start_with?("<") ? raw_path : File.expand_path(raw_path)
          return if path.start_with?(COLLECTOR_DIR)

          method_name = normalize_method(trace.method_id)
          case trace.event
          when :call, :b_call
            record_call(trace, path, method_name)
          when :return, :b_return
            record_return(trace, path, method_name)
          when :raise
            record_raise(trace, path, method_name)
          end
        end

        def record_call(trace, path, method_name)
          key = [path, method_name]
          @counts[key] += 1
          fid = "#{path}:#{method_name}##{@counts[key]}"
          write(
            "type" => "frame",
            "event" => trace.event.to_s,
            "pid" => Process.pid,
            "fid" => fid,
            "parent" => @stack.last && @stack.last[:fid],
            "method" => method_name,
            "path" => path,
            "lineno" => trace.lineno,
            "app" => application_path?(path)
          )
          @stack << { fid: fid, path: path, method: method_name }
        end

        def record_return(trace, path, method_name)
          index = @stack.rindex { |frame| frame[:path] == path && frame[:method] == method_name }
          return unless index

          frame = @stack[index]
          write(
            "type" => "return",
            "event" => trace.event.to_s,
            "pid" => Process.pid,
            "fid" => frame[:fid],
            "method" => method_name,
            "path" => path,
            "lineno" => trace.lineno,
            "app" => application_path?(path)
          )
          @stack.slice!(index..-1)
        end

        def record_raise(trace, path, method_name)
          @raise_ordinal += 1
          write(
            "type" => "raise",
            "event" => "raise",
            "pid" => Process.pid,
            "fid" => @stack.last && @stack.last[:fid],
            "method" => method_name,
            "path" => path,
            "lineno" => trace.lineno,
            "exception_class" => trace.raised_exception.class.name,
            "raise_ordinal" => @raise_ordinal,
            "app" => application_path?(path)
          )
        end

        def normalize_method(method_id)
          FramesMethod.normalize(method_id)
        end

        def application_path?(path)
          !path.start_with?("<") && path.start_with?("#{@root}/") && !path.start_with?("#{@root}/vendor/bundle/")
        end

        def write(record)
          @write_mutex.synchronize do
            @file.puts(JSON.generate(record))
            @file.flush
          end
        end
      end

      @root = File.expand_path(Dir.pwd)
      @outside_window_events = 0
      @active = false
      @stack = []
      @counts = Hash.new(0)
      @raise_ordinal = 0
      @write_mutex = Mutex.new
      # RUBYOPT loads this collector in spawned descendants too.
      # Per-process files keep their event streams separate.
      @file = File.open("#{ENV.fetch('BULLDOGGER_FRAMES_OUT')}-#{Process.pid}.jsonl", "a")
      @trace = TracePoint.new(*EVENTS) { |trace| record(trace) }
      @trace.enable
      at_exit do
        @trace.disable
        write("type" => "summary", "pid" => Process.pid, "outside_window_events" => @outside_window_events)
        @file.close
      end
    end
  end
end
