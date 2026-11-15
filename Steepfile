# frozen_string_literal: true

target :lib do
  signature "sig", "sig-deps"
  check "lib"

  # These run inside the test process of the app under observation and
  # call into its test framework (Minitest, RSpec) or TracePoint data that
  # has no signature, so they are left unchecked.
  ignore "lib/bulldogger/minitest.rb"
  ignore "lib/bulldogger/rspec.rb"
  ignore "lib/bulldogger/integrations"
  ignore "lib/bulldogger/exec_collector.rb"
  ignore "lib/bulldogger/flt_collector.rb"
  ignore "lib/bulldogger/frames_collector.rb"

  library "json", "fileutils", "digest", "open3", "shellwords", "stringio"
end
