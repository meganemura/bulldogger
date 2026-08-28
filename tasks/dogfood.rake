# frozen_string_literal: true

# Runs Bulldogger's own acceptance suite under Bulldogger itself.
#
# The unit suite cannot host this: test/test_helper.rb resets the
# Bulldogger singleton in every Minitest::Test#setup (needed so unit
# tests stay isolated from each other), which destroys an outer
# instance before it ever sees a failure. The acceptance suite never
# requires bulldogger in this process (see acceptance_helper.rb), so
# it is the one place an outer Bulldogger instance survives the run.
#
# Neither task runs by default (`rake` stays fast); both are opt-in.

desc "Run the acceptance suite under Bulldogger, proving a green run captures nothing"
task :dogfood do
  require "fileutils"
  require "open3"
  require_relative "../test/acceptance/acceptance_helper"

  root = BulldoggerAcceptanceHelper::ROOT
  output_dir = File.join(root, "tmp/bulldogger-dogfood")
  FileUtils.rm_rf(output_dir)

  require_script = "Dir[File.join(#{root.inspect}, 'test/acceptance/**/*_test.rb')].sort.each { |f| require f }"

  stdout, stderr, status = Open3.capture3(
    { "BULLDOGGER_OUTPUT_DIR" => output_dir },
    "bundle", "exec", "ruby", "-Ilib", "-Itest", "-rbulldogger/minitest", "-e", require_script,
    chdir: root
  )

  puts stdout
  warn stderr unless stderr.empty?

  abort "rake dogfood: the acceptance suite failed while running under Bulldogger itself (see output above)" unless status.success?

  evidence_files = Dir.glob(File.join(output_dir, "run-*", "*.json")).reject { |f| File.basename(f) == "index.json" }

  if evidence_files.empty?
    puts "rake dogfood: acceptance suite passed under Bulldogger; 0 evidence files were written, as a green suite should write."
  else
    abort "rake dogfood: acceptance suite passed but Bulldogger still wrote #{evidence_files.size} evidence file(s) -- " \
          "that means the zero-cost-when-green claim just broke. Files: #{evidence_files.join(', ')}"
  end
end

namespace :dogfood do
  # Runs the planted failure through the exact wiring `rake dogfood`
  # itself uses (the same `-rbulldogger/minitest` outer process, the
  # same acceptance files, in the same order) with one deliberately
  # failing test appended, instead of requiring bulldogger/minitest
  # from inside the fixture on its own. A fixture that wires itself up
  # would only re-show what test/fixtures/minitest_red/red_test.rb
  # already proves (a solo failing test captures cleanly); routing
  # through :dogfood's own invocation is what actually exercises "the
  # outer instance survives the whole acceptance run", the claim this
  # demo exists to check.
  desc "Deliberately fail a test under Bulldogger and print the evidence it captured"
  task :demo do
    require "fileutils"
    require "json"
    require "open3"
    require "tmpdir"
    require_relative "../test/acceptance/acceptance_helper"

    root = BulldoggerAcceptanceHelper::ROOT
    fixture_dir = File.join(root, "test/fixtures/dogfood")
    fixture_path = File.join(fixture_dir, "demo_test.rb")
    marker = "bulldogger-dogfood-demo-value"

    FileUtils.mkdir_p(fixture_dir)
    File.write(fixture_path, <<~RUBY)
      # frozen_string_literal: true

      # Written by `rake dogfood:demo` (see tasks/dogfood.rake) and
      # deleted as soon as that task has read its evidence. Bulldogger
      # itself is not required here -- the parent process supplies it
      # via -rbulldogger/minitest, the same way `rake dogfood` runs the
      # real acceptance suite, so this failure is captured by the same
      # instance that runs the real acceptance suite in this process
      # (Minitest may run tests in any order for a given seed, so
      # nothing here assumes this file runs last).
      require "minitest/autorun"

      class BulldoggerDogfoodDemoTest < ::Minitest::Test
        def test_deliberate_failure_for_dogfood_demo
          planted_marker = #{marker.inspect}
          api_token = "sk-dogfood-demo-secret"
          assert_equal "unreachable", planted_marker, "seeded api_token: \#{api_token.length} chars"
        end
      end
    RUBY

    begin
      Dir.mktmpdir("bulldogger-dogfood-demo-") do |output_dir|
        require_script = "(Dir[File.join(#{root.inspect}, 'test/acceptance/**/*_test.rb')].sort + " \
                          "[#{fixture_path.inspect}]).each { |f| require f }"

        stdout, stderr, status = Open3.capture3(
          { "BULLDOGGER_OUTPUT_DIR" => output_dir },
          "bundle", "exec", "ruby", "-Ilib", "-Itest", "-rbulldogger/minitest", "-e", require_script,
          chdir: root
        )

        puts stdout
        warn stderr unless stderr.empty?

        abort "rake dogfood:demo: the run passed instead of failing -- the planted test should have failed. Fix the fixture." if status.success?

        evidence_files = Dir.glob(File.join(output_dir, "run-*", "*.json")).reject { |f| File.basename(f) == "index.json" }
        abort "rake dogfood:demo: the planted test failed but Bulldogger wrote no evidence at all." if evidence_files.empty?

        records = evidence_files.map { |f| JSON.parse(File.read(f)) }
        record = records.find { |r| r.dig("test", "id").to_s.include?("BulldoggerDogfoodDemoTest") }
        unless record
          abort "rake dogfood:demo: no evidence file was for the planted test (found: " \
                "#{records.map { |r| r.dig('test', 'id') }.join(', ')}) -- something else in the acceptance " \
                "suite failed instead."
        end

        locals = Array(record["frames"]).filter_map { |f| f["locals"] }.reduce({}, :merge)

        puts
        puts "=== rake dogfood:demo: evidence from a deliberately failed test, captured by the same instance that ran the real acceptance suite ==="
        puts "capture_mode:  #{record['capture_mode']}"
        puts "frames:        #{Array(record['frames']).size}"
        puts "planted_marker in evidence: #{locals['planted_marker'].inspect}"
        puts "api_token in evidence:      #{locals['api_token'].inspect}"
        puts "==="
        puts

        # A dogfood demo that only ever runs green is indistinguishable
        # from one that captures nothing -- "missed" must fail this
        # task loudly, not print a quiet success next to it. Checked
        # first among the remaining guards: it is the primary diagnosis
        # ("dogfooding did not capture") when it fires, ahead of
        # secondary symptoms like other tests failing alongside it.
        unless record["capture_mode"] == "capture_frames"
          abort "rake dogfood:demo: capture_mode was #{record['capture_mode'].inspect}, not \"capture_frames\" -- " \
                "dogfooding did not actually capture anything. Failing on purpose."
        end

        if records.size > 1
          abort "rake dogfood:demo: expected exactly 1 evidence file (the planted failure), got " \
                "#{records.size} -- the real acceptance suite failed alongside the planted test: " \
                "#{records.map { |r| r.dig('test', 'id') }.join(', ')}."
        end

        expected_value = { "value" => marker.inspect }
        unless locals["planted_marker"] == expected_value
          abort "rake dogfood:demo: planted local \"planted_marker\" was not found in the evidence as expected " \
                "(#{expected_value.inspect}), got #{locals['planted_marker'].inspect}."
        end

        unless locals.dig("api_token", "redacted") == true
          abort "rake dogfood:demo: planted local \"api_token\" was not redacted in the evidence."
        end

        # Per-failure evidence alone proves the instance was alive at
        # the moment the plant failed, wherever the seed put it in the
        # 16-test run -- not that it survived to the end of the whole
        # suite. index.json is written only when Bulldogger.finish runs
        # at Minitest.after_run (see acceptance_helper.rb's run_dir_for
        # and minitest_integration_test.rb, which check the same file
        # for the same reason), so its presence is what actually proves
        # survival through the real acceptance suite, not just wording.
        run_dir = File.dirname(evidence_files.first)
        index_path = File.join(run_dir, "index.json")
        unless File.exist?(index_path)
          abort "rake dogfood:demo: #{index_path} is missing -- Bulldogger.finish never ran, so this run does not " \
                "prove the instance survived to the end of the acceptance suite."
        end

        puts "rake dogfood:demo: capture_mode is \"capture_frames\", the planted local is present, api_token is " \
             "redacted, and index.json proves the instance survived the whole acceptance run."
      end
    ensure
      FileUtils.rm_f(fixture_path)
      FileUtils.rmdir(fixture_dir) if Dir.exist?(fixture_dir) && Dir.empty?(fixture_dir)
    end
  end
end
