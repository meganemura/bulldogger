# frozen_string_literal: true

module Bulldogger
  # Turns a :raise TracePoint event into a bounded array of frame
  # descriptions. Prefers DEBUGGER__.capture_frames, which yields every
  # frame's Binding; falls back to TracePoint#binding (raising frame
  # only) plus the exception's backtrace locations (position only, no
  # locals) when `debug/frame_info` cannot be loaded. That fallback is
  # not a rare edge case: `debug` is a bundled gem, not a default gem,
  # so under Bundler it is only present when the app's own Gemfile asks
  # for it.
  class FrameSource
    def initialize(config:, formatter:, redactor:, skip_path_prefix: self.class.default_skip_path_prefix)
      @config = config
      @formatter = formatter
      @redactor = redactor
      @skip_path_prefix = skip_path_prefix
      @mode = nil
    end

    # skip_path_prefix must be *this library's* lib directory, not the
    # app's. capture_frames drops every frame whose path starts with
    # the given prefix; pointing it at the app's own lib directory was
    # measured to make the app's frames disappear instead of ours,
    # leaving a snapshot with zero useful frames.
    def self.default_skip_path_prefix
      File.expand_path("..", __dir__)
    end

    # :auto resolves once, here, and is cached for the life of this
    # object -- not re-checked on every raise, which would repeat a
    # `require` check thousands of times in a large suite.
    def resolve!
      @mode ||= resolve_mode
      self
    end

    def mode
      @mode ||= resolve_mode
    end

    def capture(tp)
      mode == :capture_frames ? capture_via_debugger(tp) : capture_degraded(tp)
    end

    private

    def resolve_mode
      configured = @config.frame_source
      return :degraded if configured == :degraded

      # Explicit :capture_frames still needs this require to have run --
      # it is what defines the DEBUGGER__ constant this class calls
      # into. Only :degraded can skip it; :auto needs the result to
      # decide, and explicit :capture_frames needs it as a side effect
      # even though the caller has already made the decision.
      available = capture_frames_available?
      return available ? :capture_frames : :degraded if configured == :auto

      configured
    end

    def capture_frames_available?
      require "debug/frame_info"
      DEBUGGER__.respond_to?(:capture_frames)
    rescue LoadError
      false
    end

    def capture_via_debugger(tp)
      frame_infos = DEBUGGER__.capture_frames(@skip_path_prefix)
      kept = frame_infos.first(@config.max_frames)
      frames = kept.each_with_index.map { |frame_info, index| build_frame(frame_info, index) }
      [frames, frame_infos.size - kept.size]
    end

    def build_frame(frame_info, index)
      location = frame_info.location
      frame = {
        "index" => index,
        "path" => location&.path,
        "line" => location&.lineno,
        "label" => frame_info.name,
        "self" => @formatter.format_self(frame_info.self)
      }
      binding = frame_info.binding
      locals, locals_omitted = binding ? build_locals(binding) : [{}, 0]
      frame["locals"] = locals
      frame["locals_omitted"] = locals_omitted if locals_omitted.positive?
      frame
    end

    def capture_degraded(tp)
      locations = degraded_locations(tp)
      kept = locations.first(@config.max_frames)
      frames = kept.each_with_index.map { |location, index| build_degraded_frame(tp, location, index) }
      [frames, locations.size - kept.size]
    end

    def degraded_locations(tp)
      locations = tp.raised_exception.backtrace_locations
      return locations if locations

      # caller_locations here includes this hook's own frames (unlike
      # backtrace_locations, which is the app's own backtrace and never
      # contains ours), so they need the same prefix filter.
      Array(caller_locations).reject { |location| location.path&.start_with?(@skip_path_prefix) }
    end

    def build_degraded_frame(tp, location, index)
      frame = {
        "index" => index,
        "path" => location.path,
        "line" => location.lineno,
        "label" => location.label
      }
      if index.zero?
        locals, locals_omitted = build_frame0_locals(tp)
        frame["locals"] = locals
        frame["locals_omitted"] = locals_omitted if locals_omitted.positive?
        frame["self"] = @formatter.format_self(tp.self)
      else
        frame["locals_unavailable"] = true
      end
      frame
    end

    def build_frame0_locals(tp)
      binding = tp.binding
      binding ? build_locals(binding) : [{}, 0]
    end

    def build_locals(binding)
      names = binding.local_variables
      kept = names.first(@config.max_locals)
      locals = {}
      kept.each { |name| locals[name.to_s] = build_local_entry(name, binding) }
      [locals, names.size - kept.size]
    end

    def build_local_entry(name, binding)
      return { "redacted" => true, "reason" => "name" } if @redactor.redact_name?(name)

      @formatter.format(binding.local_variable_get(name))
    end
  end
end
