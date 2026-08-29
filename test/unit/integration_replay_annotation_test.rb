# frozen_string_literal: true

require "test_helper"
require "bulldogger/integrations/minitest"
require "bulldogger/integrations/rspec"

# Both integrations read the just-written evidence file back to find
# its "replay" key, so the annotated failure message can also name the
# trace. That JSON.parse(File.read(path)) has its own rescue branch
# for a path that turns out to be unreadable or malformed -- covered
# here directly (a nonexistent path is the simplest way to trigger a
# real SystemCallError) rather than through a full fixture process,
# which has no way to make the evidence file disappear between being
# written and being read back.
class IntegrationReplayAnnotationTest < Minitest::Test
  def test_minitest_reporter_replay_path_returns_nil_for_an_unreadable_evidence_file
    reporter = Bulldogger::Minitest::Reporter.new

    assert_nil reporter.send(:replay_path, "/nonexistent/evidence.json")
  end

  def test_rspec_annotate_falls_back_to_the_evidence_only_suffix_for_an_unreadable_evidence_file
    exception = RuntimeError.new("boom")

    Bulldogger::RSpec.annotate!(exception, "/nonexistent/evidence.json")

    assert_equal "boom\nbulldogger evidence: /nonexistent/evidence.json", exception.message
  end
end
