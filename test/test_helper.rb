# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "bulldogger"
require "minitest/autorun"
require "tmpdir"
require "hegel"

module BulldoggerTestHelper
  # Bulldogger memoizes one Config/Capture/Run/Evidence per process.
  # Each test needs its own, or the TracePoint, the pending ring, and
  # the run directory leak between tests and make test order matter.
  # output_dir points at a fresh Dir.mktmpdir so no test writes into
  # this repository's own tmp/bulldogger.
  def bulldogger_reset!
    Bulldogger.stop if Bulldogger.running?
    %i[@config @capture @run @evidence].each do |ivar|
      Bulldogger.instance_variable_set(ivar, nil)
    end
    Bulldogger.config.output_dir = Dir.mktmpdir("bulldogger-test-")
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
