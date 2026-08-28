# frozen_string_literal: true

require_relative "target"

module Bulldogger
  module Probe
    # Turns "Klass#method" / "Klass.method" strings into Targets,
    # failing before any TracePoint is enabled. Resolving every target
    # up front (not lazily, on first call) is the contract's own
    # requirement: a probe session must not let bad instrumentation
    # surface only after the caller's code has already started
    # running.
    module TargetResolver
      INSTANCE_PATTERN = /\A(.+)#(.+)\z/
      SINGLETON_PATTERN = /\A(.+)\.(.+)\z/

      module_function

      def resolve!(target_strings)
        target_strings.map { |s| resolve_one!(s) }
      end

      def resolve_one!(target_string)
        owner_name, method_name, kind = split(target_string)
        owner = resolve_constant!(owner_name, target_string)
        unbound_method = resolve_unbound_method!(owner, method_name, kind, target_string)
        assert_targetable!(unbound_method, target_string)
        Target.new(target_string, unbound_method)
      end

      def split(target_string)
        if (m = INSTANCE_PATTERN.match(target_string))
          [m[1], m[2], :instance]
        elsif (m = SINGLETON_PATTERN.match(target_string))
          [m[1], m[2], :singleton]
        else
          raise ArgumentError,
                "bulldogger: invalid probe target #{target_string.inspect} " \
                '(expected "Klass#method" or "Klass.method")'
        end
      end

      # const_get(name, false) at each nesting level (not a single
      # Object.const_get("A::B")) so a wrong nested name fails with
      # the segment that is actually missing, and so this never
      # accidentally resolves a same-named top-level constant that
      # const_get's own inherit-search could reach from a deeper
      # module (the `false` argument).
      def resolve_constant!(owner_name, target_string)
        owner_name.split("::").reject(&:empty?).reduce(Object) do |mod, name|
          mod.const_get(name, false)
        end
      rescue NameError
        raise NameError,
              "bulldogger: no constant #{owner_name.inspect} for probe target #{target_string.inspect}"
      end

      def resolve_unbound_method!(owner, method_name, kind, target_string)
        if kind == :instance
          owner.instance_method(method_name.to_sym)
        else
          owner.method(method_name.to_sym).unbind
        end
      rescue NameError
        raise NameError, "bulldogger: no method for probe target #{target_string.inspect}"
      end

      # The only way to learn that a method is C-implemented is to
      # actually try targeting it: UnboundMethod itself resolves fine
      # for a C method (Array.instance_method(:push) succeeds); it is
      # TracePoint#enable(target:) that raises ArgumentError (measured:
      # "specified target is not supported", Array#push). The probe
      # TracePoint built here is disabled again immediately -- its only
      # purpose is to surface that error before any of the caller's
      # targets go live.
      def assert_targetable!(unbound_method, target_string)
        probe_tp = TracePoint.new(:call) {}
        probe_tp.enable(target: unbound_method)
        probe_tp.disable
      rescue ArgumentError
        raise ArgumentError,
              "bulldogger: probe target #{target_string.inspect} is a C-implemented method and can't be traced"
      end
    end
  end
end
