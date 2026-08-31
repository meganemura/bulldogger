# frozen_string_literal: true

require "test_helper"
require "bulldogger/integrations/minitest"
require "bulldogger/integrations/rspec"

# Both integrations read the evidence file to select the useful path.
# A fixture cannot remove that file between the write and the annotation,
# so this test uses an unreadable path to cover the fallback guidance.
class IntegrationReplayAnnotationTest < Minitest::Test
  def test_minitest_reporter_prints_failure_output_to_its_io
    io = StringIO.new
    reporter = Bulldogger::Minitest::Reporter.new(io)

    reporter.send(:annotate!, RuntimeError.new("boom"), "/nonexistent/evidence.json")

    assert_equal "bulldogger evidence: /nonexistent/evidence.json\n", io.string
  end

  def test_rspec_annotate_falls_back_to_the_evidence_only_suffix_for_an_unreadable_evidence_file
    exception = RuntimeError.new("boom")

    Bulldogger::RSpec.annotate!(exception, "/nonexistent/evidence.json")

    assert_equal "boom\nbulldogger evidence: /nonexistent/evidence.json", exception.message
  end

  def test_missed_capture_says_that_the_snapshot_has_no_frames
    Dir.mktmpdir do |dir|
      path = File.join(dir, "evidence.json")
      File.write(path, JSON.generate("capture_mode" => "missed", "frames" => []))
      exception = RuntimeError.new("boom")

      Bulldogger::RSpec.annotate!(exception, path)

      assert_equal "boom\nbulldogger evidence: #{path} (snapshot holds no frames)", exception.message
    end
  end

  def test_incomplete_evidence_does_not_change_failure_reporting
    Dir.mktmpdir do |dir|
      path = File.join(dir, "evidence.json")
      File.write(path, "{}")
      exception = RuntimeError.new("boom")

      Bulldogger::RSpec.annotate!(exception, path)

      assert_equal "boom\nbulldogger evidence: #{path} (frames do not show where the value came from)", exception.message
    end
  end
end
