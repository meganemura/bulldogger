# frozen_string_literal: true

# A tiny call-graph fixture for the probe proportionality measurement:
# probe's cost scales with calls to its targeted method (M), not with
# the total call count across the workload (N). A wrapper method
# dispatches to one of two leaf methods, matching an app's actual
# shape (a caller that routes to one of several handlers) rather than
# a driver loop calling leaf methods directly. Every Ruby-defined
# method here counts its own calls, so M (calls to the probed leaf)
# and N (calls across every method in this file) are read off real
# counters after a run, never estimated from the iteration counts that
# drove it.
#
# `hit` and `noise` share the same arity (one required positional) and
# return shape (Integer), so a shift in the M/N mix cannot confound
# the timing with a workload-shape change instead of isolating the
# call-count effect proportionality.rake exists to measure.
module Proportionality
  class Target
    attr_reader :calls

    def initialize
      @calls = 0
    end

    # This is the only method proportionality.rake ever probes.
    def hit(i)
      @calls += 1
      i + 1
    end
  end

  class Other
    attr_reader :calls

    def initialize
      @calls = 0
    end

    # Stands in for every call that probe, targeted at Target#hit
    # alone, never dispatches on. It still counts toward N.
    def noise(i)
      @calls += 1
      i + 1
    end
  end

  class App
    attr_reader :calls, :target, :other

    def initialize
      @target = Target.new
      @other = Other.new
      @calls = 0
    end

    # One wrapper hop per invocation: the call graph is
    # App#step -> Target#hit or App#step -> Other#noise, not a flat
    # driver loop calling leaves directly.
    def step(i, hit:)
      @calls += 1
      hit ? @target.hit(i) : @other.noise(i)
    end
  end
end
