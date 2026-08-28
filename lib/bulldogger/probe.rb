# frozen_string_literal: true

require_relative "redactor"
require_relative "formatter"
require_relative "probe/session"
require_relative "probe/comparator"

module Bulldogger
  # Targeted capture: instead of a snapshot at the moment a test fails
  # (Capture) or a full trace of every call (Record), a probe watches
  # one or a few named methods across many calls and reports the
  # *shape* of what it saw -- argument and return classes, nil counts,
  # raise-exit counts, callers -- so a coding agent can answer
  # "what does this method actually receive and return" without
  # reading every call site by hand.
  #
  # See lib/bulldogger/probe/session.rb for the mechanism: one
  # TracePoint per target method (:call/:return, targeted -- cheap and
  # strictly filtered) plus one shared, ref-counted pair of untargeted
  # TracePoints (:raise/:rescue, per contract-verbs.md the only way to
  # tell a raise-exit apart from a method that legitimately returns
  # nil).
  module Probe
    def self.start(target_strings, config:, run:)
      Session.start(target_strings, config: config, run: run)
    end

    def self.call(target_strings, config:, run:, &block)
      Session.run(target_strings, config: config, run: run, &block)
    end

    def self.compare(path_a, path_b)
      Comparator.compare(path_a, path_b)
    end
  end
end
