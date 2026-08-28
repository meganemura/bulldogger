# frozen_string_literal: true

module Bulldogger
  # Decides whether a name (a local variable, a Hash key) should hide
  # its value. This check runs on the name alone, before any value is
  # touched: calling `inspect` on a secret-shaped object and then
  # discarding the result still risks the secret leaking (into a log,
  # into a raised error from a hostile #inspect), so the name check
  # must gate the inspect call, not follow it.
  class Redactor
    def initialize(patterns)
      @patterns = patterns
    end

    def redact_name?(name)
      matches?(name)
    end

    def redact_key?(key)
      matches?(key)
    end

    private

    def matches?(name)
      text = name.to_s
      @patterns.any? { |pattern| pattern.match?(text) }
    end
  end
end
