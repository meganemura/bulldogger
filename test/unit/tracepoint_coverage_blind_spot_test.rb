# frozen_string_literal: true

require "test_helper"
require "open3"
require "json"
require "tmpdir"

# The minimal reproduction every other direct-call test in this
# directory points at instead of citing an internal task document:
# stdlib Coverage cannot observe a line executing while a TracePoint
# callback is already on the stack. Measured directly (ruby 4.0.6):
# `TracePoint.allow_reentry` exists specifically because the VM
# suppresses further event-hook dispatch while already inside one
# hook's callback, and Coverage's own line counting rides that same
# event-hook mechanism, so it is suppressed the same way -- simplecov
# rides the same stdlib Coverage underneath, so it is not an
# alternative.
#
# If this test ever starts failing, Ruby has fixed this limitation:
# read that as the underlying fact changing, not as a regression, and
# retire the empty ledger in tasks/coverage.rake along with it.
class TracepointCoverageBlindSpotTest < Minitest::Test
  def test_a_line_run_only_inside_a_tracepoint_callback_is_invisible_to_coverage
    result = run_repro_in_a_scrubbed_subprocess

    # Both lines really ran -- proven by a side effect Coverage cannot
    # suppress, the same "did it actually execute" evidence the task
    # report's own probe used.
    assert_equal %w[direct hooked], result["calls"]

    # Coverage saw the directly-called line...
    assert_equal 1, result["direct_line_count"]
    # ...but not the line that only ever ran from inside the
    # TracePoint callback, even though $calls above proves it ran.
    assert_includes [0, nil], result["hooked_line_count"]
  end

  private

  # A subprocess, not an in-process Coverage.start/result call: this
  # process may itself be running under rake coverage's own live
  # Coverage measurement (tasks/coverage.rake), and starting a second
  # Coverage in-process would raise, while Coverage.result would stop
  # the real, live measurement out from under the gate that is running
  # this very test. RUBYOPT/BULLDOGGER_COVERAGE_DIR are explicitly
  # cleared so the child does not inherit the coverage boot script and
  # collide with this repro's own Coverage.start.
  def run_repro_in_a_scrubbed_subprocess
    Dir.mktmpdir("bulldogger-blind-spot-repro-") do |dir|
      # Two files, not one: Coverage.start cannot retroactively
      # instrument the file it is itself running from -- that file's
      # own ISeq is already compiled, uninstrumented, before any of
      # its own lines (Coverage.start included) can run (the same
      # reason lib/bulldogger/version.rb needs test_helper.rb's own
      # `load` trick). Coverage.start runs in boot.rb; the methods it
      # measures live in target.rb, required afterward.
      boot_path = File.join(dir, "boot.rb")
      target_path = File.join(dir, "target.rb")
      File.write(target_path, REPRO_TARGET)
      File.write(boot_path, REPRO_BOOT.sub("TARGET_PATH", target_path.inspect))

      stdout, stderr, status = Open3.capture3(
        { "RUBYOPT" => nil, "BULLDOGGER_COVERAGE_DIR" => nil },
        RbConfig.ruby, boot_path
      )
      assert status.success?, "repro subprocess failed:\n#{stderr}"
      JSON.parse(stdout)
    end
  end

  REPRO_BOOT = <<~'RUBY'
    require "coverage"
    Coverage.start(lines: true)
    require TARGET_PATH
  RUBY

  REPRO_TARGET = <<~'RUBY'
    require "json"

    $calls = []

    DIRECT_LINE = __LINE__ + 2
    def call_directly
      $calls << "direct"
    end

    HOOKED_LINE = __LINE__ + 2
    def call_via_hook
      $calls << "hooked"
    end

    call_directly

    def through_hook
      nil
    end

    tp = TracePoint.new(:call) do |t|
      call_via_hook if t.method_id == :through_hook
    end
    tp.enable
    through_hook
    tp.disable

    lines = Coverage.result[__FILE__][:lines]
    puts JSON.generate(
      "calls" => $calls,
      "direct_line_count" => lines[DIRECT_LINE - 1],
      "hooked_line_count" => lines[HOOKED_LINE - 1]
    )
  RUBY
end
