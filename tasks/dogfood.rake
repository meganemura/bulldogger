# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../test/acceptance/acceptance_helper"

# Runs repository suites through an outer instance and checks its evidence.
# This task does not implement product capture or integration behavior.
#
# Every Minitest::Test setup stops Bulldogger and clears its default state for
# test isolation. That reset is correct, so dogfood assigns a separate observer.
# Before this separation, an isolated failure used capture_frames with 20
# frames. The same failure used missed with zero frames in the unit suite.
module BulldoggerDogfood
  module_function

  def suites(root)
    {
      "unit" => Dir[File.join(root, "test/{unit,property}/**/*_test.rb")].sort,
      "acceptance" => Dir[File.join(root, "test/acceptance/**/*_test.rb")].sort
    }
  end

  def run(root:, files:, output_dir:)
    # The assigned instance survives resets of Bulldogger.default inside the
    # unit suite, while the integration fallback still serves normal callers.
    require_script = <<~RUBY
      Bulldogger::Minitest.instance = Bulldogger::Instance.new
      #{files.inspect}.each { |file| require file }
    RUBY

    Open3.capture3(
      { "BULLDOGGER_OUTPUT_DIR" => output_dir },
      "bundle", "exec", "ruby", "-Ilib", "-Itest", "-rbulldogger/minitest", "-e", require_script,
      chdir: root
    )
  end

  def evidence_files(output_dir)
    Dir.glob(File.join(output_dir, "run-*", "*.json")).reject { |file| File.basename(file) == "index.json" }
  end

  def print_result(stdout, stderr)
    puts stdout
    warn stderr unless stderr.empty?
  end

  def verify_demo(output_dir:, suite_name:, marker:)
    files = evidence_files(output_dir)
    abort "rake dogfood:demo: #{suite_name} wrote no evidence." if files.empty?

    records = files.map { |file| JSON.parse(File.read(file)) }
    record = records.find { |item| item.dig("test", "id").to_s.include?("BulldoggerDogfoodDemoTest") }
    abort "rake dogfood:demo: #{suite_name} wrote no evidence for the planted test." unless record

    locals = Array(record["frames"]).filter_map { |frame| frame["locals"] }.reduce({}, :merge)
    frame_count = Array(record["frames"]).size

    puts "#{suite_name} capture_mode: #{record['capture_mode']}"
    puts "#{suite_name} frames: #{frame_count}"

    unless record["capture_mode"] == "capture_frames" && frame_count.positive?
      abort "rake dogfood:demo: #{suite_name} captured #{record['capture_mode'].inspect} with #{frame_count} frames."
    end

    expected_value = { "value" => marker.inspect }
    abort "rake dogfood:demo: #{suite_name} did not capture planted_marker." unless locals["planted_marker"] == expected_value
    abort "rake dogfood:demo: #{suite_name} did not redact api_token." unless locals.dig("api_token", "redacted") == true
    abort "rake dogfood:demo: #{suite_name} wrote #{records.size} evidence files." unless records.size == 1

    index_path = File.join(File.dirname(files.first), "index.json")
    abort "rake dogfood:demo: #{suite_name} did not write index.json." unless File.exist?(index_path)

    [record["capture_mode"], frame_count]
  end
end

desc "Run the unit and acceptance suites under Bulldogger"
task :dogfood do
  root = BulldoggerAcceptanceHelper::ROOT
  base_output_dir = File.join(root, "tmp/bulldogger-dogfood")
  FileUtils.rm_rf(base_output_dir)

  BulldoggerDogfood.suites(root).each do |suite_name, files|
    output_dir = File.join(base_output_dir, suite_name)
    stdout, stderr, status = BulldoggerDogfood.run(root: root, files: files, output_dir: output_dir)
    BulldoggerDogfood.print_result(stdout, stderr)
    abort "rake dogfood: #{suite_name} failed." unless status.success?

    evidence_files = BulldoggerDogfood.evidence_files(output_dir)
    abort "rake dogfood: #{suite_name} wrote #{evidence_files.size} evidence files." unless evidence_files.empty?

    puts "rake dogfood: #{suite_name} passed with 0 evidence files."
  end
end

namespace :dogfood do
  desc "Deliberately fail under the unit and acceptance suites and verify captured evidence"
  task :demo do
    root = BulldoggerAcceptanceHelper::ROOT
    fixture_dir = File.join(root, "test/fixtures/dogfood")
    fixture_path = File.join(fixture_dir, "demo_test.rb")
    marker = "bulldogger-dogfood-demo-value"

    FileUtils.mkdir_p(fixture_dir)
    File.write(fixture_path, <<~RUBY)
      # frozen_string_literal: true

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
      BulldoggerDogfood.suites(root).each do |suite_name, files|
        Dir.mktmpdir("bulldogger-dogfood-demo-") do |output_dir|
          stdout, stderr, status = BulldoggerDogfood.run(
            root: root,
            files: files + [fixture_path],
            output_dir: output_dir
          )
          BulldoggerDogfood.print_result(stdout, stderr)
          abort "rake dogfood:demo: #{suite_name} passed instead of failing." if status.success?

          BulldoggerDogfood.verify_demo(output_dir: output_dir, suite_name: suite_name, marker: marker)
        end
      end
    ensure
      FileUtils.rm_f(fixture_path)
      FileUtils.rmdir(fixture_dir) if Dir.exist?(fixture_dir) && Dir.empty?(fixture_dir)
    end
  end
end
