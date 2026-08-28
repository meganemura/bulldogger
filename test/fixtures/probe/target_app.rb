# frozen_string_literal: true

# A tiny stand-in app for probe's unit and acceptance tests: real
# classes with real methods, not mocks, so a probe session observes
# genuine TracePoint(:call, :return) events rather than a hand-built
# fixture of what those events "should" look like.
#
# Defined at the top level, not nested in a fixture wrapper module:
# probe targets are resolved by string ("Billing::Invoice#amount"),
# and TargetResolver walks that path from Object, matching
# contract-verbs.md's own example labels exactly.
module Billing
  class Invoice
    # A required positional arg plus a keyword with a default proves
    # both "actual argument recorded by name" and "a default-filled
    # keyword argument is visible at :call time" (contract-verbs.md's
    # measured `discount: nil` example) with a single target.
    def amount(mult, discount: nil)
      base = mult * 10
      discount ? base - discount : base
    end

    # api_token's name matches the default redact_patterns (/token/i)
    # -- this is the method that proves a redacted argument's sample
    # never carries the raw value.
    def charge(api_token)
      api_token.to_s.length
    end

    # Always raises: the method that proves a raise-exit is counted
    # as raised_exits, not fabricated as a nil return.
    def blows_up
      raise ArgumentError, "boom"
    end

    # Raises internally but recovers before returning: proves a
    # caught-and-handled raise inside the target still counts as a
    # normal, non-raise-exit return -- the opposite of blows_up.
    def recovers
      raise "internal"
    rescue RuntimeError
      :recovered
    end

    # Returns self, whose default #inspect embeds an object address
    # (e.g. "#<Billing::Invoice:0x00007f...>"). Two probe runs create
    # two different Invoice instances, so this is what probe_compare's
    # address normalization has to see through to call unchanged code
    # "identical".
    def snapshot
      self
    end
  end
end

module Order
  # A singleton/class-method target ("Klass.method" spelling).
  def self.total(qty)
    qty * 100
  end
end

module Untouched
  # Never named as a probe target anywhere in the test suite: exists
  # purely so a test can call it while a *different* method is being
  # probed, and assert no event was ever recorded for it --
  # TracePoint#enable(target:)'s filtering is strict (measured), and
  # this is the negative-case proof of that.
  def self.ping
    :pong
  end
end
