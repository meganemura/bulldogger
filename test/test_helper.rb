# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "bulldogger"
require "minitest/autorun"
require "tmpdir"
require "hegel"

# lib/bulldogger/version.rb loads before rake coverage's own Coverage.
# start ever runs: with BUNDLE_GEMFILE inherited (true for every
# process this gate spawns), RubyGems' own startup activates Bundler
# and evaluates this gem's gemspec -- which require_relatives this
# file -- before any RUBYOPT -r flag is processed, the coverage boot
# script included (confirmed directly: `defined?(Bulldogger::VERSION)`
# already reports "constant" by the time that boot script's own first
# line runs). A file compiled before Coverage.start can never be
# instrumented by a later `require` of the same path (a no-op once
# $LOADED_FEATURES already has it); `load`ing it again forces a fresh
# compile, which Coverage.start -- already running by the time any
# test file loads -- does instrument. Scoped to a coverage run only
# (BULLDOGGER_COVERAGE_DIR is the same flag tasks/coverage.rake sets),
# so a plain `rake test` run never re-evaluates this file and never
# sees the "already initialized constant" warning that re-assigning it
# would otherwise print under `-w`.
if ENV["BULLDOGGER_COVERAGE_DIR"]
  original_verbose = $VERBOSE
  $VERBOSE = nil
  load File.expand_path("../lib/bulldogger/version.rb", __dir__)
  $VERBOSE = original_verbose
end

module BulldoggerTestHelper
  # Bulldogger memoizes one Config/Capture/Run/Evidence per process.
  # Each test needs its own, or the TracePoint, the pending ring, and
  # the run directory leak between tests and make test order matter.
  # output_dir points at a fresh Dir.mktmpdir so no test writes into
  # this repository's own tmp/bulldogger.
  def bulldogger_reset!
    Bulldogger.stop if Bulldogger.running?
    Bulldogger.instance_variable_set(:@default, nil)
    Bulldogger.config.output_dir = Dir.mktmpdir("bulldogger-test-")
    Bulldogger.config.replay_on_failure = false
  end

  # Minitest 6 moved Object#stub into the separate minitest-mock gem;
  # adding that dependency was not asked for, so the one or two call
  # sites that need a temporary singleton method write it directly.
  # define_singleton_method with a bound Method restores the original
  # implementation rather than merely calling it. Both redefinitions
  # are intentional, so -w's "method redefined" warning is suppressed
  # around them rather than left to print on every run.
  def stub_singleton_method(receiver, name, value)
    original = receiver.method(name)
    previous_verbose = $VERBOSE
    $VERBOSE = nil
    receiver.define_singleton_method(name) { |*| value }
    $VERBOSE = previous_verbose
    yield
  ensure
    $VERBOSE = nil
    receiver.define_singleton_method(name, original)
    $VERBOSE = previous_verbose
  end
end

module Minitest
  class Test
    include BulldoggerTestHelper
    include Hegel::Syntax::Methods

    def setup
      bulldogger_reset!
    end

    def teardown
      Bulldogger.stop if Bulldogger.running?
    end
  end
end
