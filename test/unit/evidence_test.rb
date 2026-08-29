# frozen_string_literal: true

require "test_helper"
require "json"
require "fileutils"

class EvidenceTest < Minitest::Test
  def test_record_failure_writes_the_documented_schema
    Bulldogger.start

    exception = trigger_raise
    path = Bulldogger.record_failure(
      exception: exception,
      test: { framework: "minitest", id: "TestFoo#test_bar", file: "test/test_foo.rb", line: 12 }
    )

    assert File.absolute_path?(path)
    assert File.exist?(path)

    data = JSON.parse(File.read(path))
    assert_equal 1, data["schema_version"]
    assert_equal "bulldogger", data["tool"]["name"]
    assert_equal Bulldogger::VERSION, data["tool"]["version"]
    assert data["captured_at"]
    assert_includes %w[capture_frames degraded missed], data["capture_mode"]
    assert_equal "minitest", data["test"]["framework"]
    assert_equal "TestFoo#test_bar", data["test"]["id"]
    assert_equal "test/test_foo.rb", data["test"]["file"]
    assert_equal 12, data["test"]["line"]
    assert_equal "RuntimeError", data["exception"]["class"]
    assert_equal "boom", data["exception"]["message"]
    assert_kind_of Array, data["exception"]["backtrace"]
    assert_kind_of Array, data["frames"]
    assert_kind_of Hash, data["limits"]
    assert_equal File.join(Bulldogger.skill_path, "SKILL.md"), data["skill"]
    assert File.file?(data["skill"])
  end

  def test_record_failure_omits_skill_when_the_skill_is_missing
    Bulldogger::Skill.stub(:file, nil) do
      path = Bulldogger.record_failure(
        exception: trigger_raise,
        test: { framework: "minitest", id: "x", file: "f.rb", line: 1 }
      )

      refute JSON.parse(File.read(path)).key?("skill")
    end
  end

  def test_a_huge_exception_message_is_truncated_and_marked
    Bulldogger.start

    exception = trigger_huge_message
    path = Bulldogger.record_failure(
      exception: exception,
      test: { framework: "minitest", id: "x", file: "f.rb", line: 1 }
    )
    data = JSON.parse(File.read(path))

    limit = Bulldogger.config.max_value_length * 5
    assert_equal true, data["exception"]["message_truncated"]
    assert_equal 6000, data["exception"]["message_original_length"]
    assert_equal limit + 1, data["exception"]["message"].length # +1 for the trailing "…"
  end

  # exception.class practically never raises for a real exception, but
  # a class whose own singleton #name does is exactly the case
  # exception_class_name's `rescue Exception` guards against -- the
  # same "never let a hostile object break capture" rule Formatter's
  # own safe_class_name follows.
  def test_an_exception_class_with_a_broken_name_falls_back_to_object
    Bulldogger.start

    exception = trigger_broken_class_name
    path = Bulldogger.record_failure(
      exception: exception,
      test: { framework: "minitest", id: "x", file: "f.rb", line: 1 }
    )
    data = JSON.parse(File.read(path))

    assert_equal "Object", data["exception"]["class"]
  end

  def test_record_failure_for_an_evicted_exception_names_the_reason_evicted
    Bulldogger.config.max_pending = 1
    Bulldogger.start

    evicted_exception = trigger_raise
    trigger_raise # pushes the first exception out of the ring

    path = Bulldogger.record_failure(
      exception: evicted_exception,
      test: { framework: "minitest", id: "x", file: "f.rb", line: 1 }
    )
    data = JSON.parse(File.read(path))

    assert_equal "missed", data["capture_mode"]
    assert_equal "evicted", data["frames_unavailable_reason"]
  end

  # Distinct from both "capture_disabled" (the tool never subscribed)
  # and "evicted" (it subscribed, captured, then the ring outgrew it):
  # this exception was simply never raised while capture was running,
  # so it never entered the ring at all.
  def test_record_failure_for_a_never_raised_exception_names_the_reason_not_captured
    Bulldogger.start
    never_raised = RuntimeError.new("built but never raised")

    path = Bulldogger.record_failure(
      exception: never_raised,
      test: { framework: "minitest", id: "x", file: "f.rb", line: 1 }
    )
    data = JSON.parse(File.read(path))

    assert_equal "missed", data["capture_mode"]
    assert_equal "not_captured", data["frames_unavailable_reason"]
  end

  def test_record_failure_without_a_snapshot_is_marked_missed
    exception =
      begin
        raise "never captured"
      rescue RuntimeError => e
        e
      end

    path = Bulldogger.record_failure(
      exception: exception,
      test: { framework: "minitest", id: "x", file: "f.rb", line: 1 }
    )
    data = JSON.parse(File.read(path))

    assert_equal "missed", data["capture_mode"]
    assert_equal [], data["frames"]
    # Bulldogger.start was never called in this test, so the tool is
    # enabled but not running -- the one case frames_unavailable_reason
    # "capture_disabled" is meant for. A disabled *switch* is a
    # different case entirely and record_failure refuses to write at
    # all for that one (see test_disabled_switch_* below).
    assert_equal "capture_disabled", data["frames_unavailable_reason"]
  end

  def test_disabled_switch_makes_record_failure_write_nothing
    Bulldogger.config.enabled = false
    output_dir = Bulldogger.config.output_dir

    exception = trigger_raise
    path = Bulldogger.record_failure(
      exception: exception,
      test: { framework: "minitest", id: "x", file: "f.rb", line: 1 }
    )

    assert_nil path
    assert_equal [], Dir.children(output_dir)
  end

  def test_disabled_switch_makes_finish_write_nothing
    Bulldogger.config.enabled = false
    output_dir = Bulldogger.config.output_dir

    Bulldogger.record_failure(
      exception: trigger_raise,
      test: { framework: "minitest", id: "x", file: "f.rb", line: 1 }
    )
    Bulldogger.finish

    assert_equal [], Dir.children(output_dir)
  end

  # run_dir is public API, so it is reachable by a caller who never
  # goes through record_failure. The switch has to hold there too.
  def test_disabled_switch_makes_run_dir_create_nothing
    Bulldogger.config.enabled = false
    output_dir = Bulldogger.config.output_dir

    assert_nil Bulldogger.run_dir
    assert_equal [], Dir.children(output_dir)
  end

  def test_finish_without_any_failure_creates_no_run_directory
    output_dir = Bulldogger.config.output_dir

    Bulldogger.finish

    assert_equal [], Dir.children(output_dir)
  end

  def test_finish_writes_index_with_all_failures_and_a_latest_symlink
    Bulldogger.start

    exception1 = trigger_raise
    exception2 = trigger_raise
    Bulldogger.record_failure(exception: exception1, test: { framework: "minitest", id: "a", file: "f.rb", line: 1 })
    Bulldogger.record_failure(exception: exception2, test: { framework: "minitest", id: "b", file: "f.rb", line: 2 })
    run_dir = Bulldogger.run_dir

    Bulldogger.finish

    index = JSON.parse(File.read(File.join(run_dir, "index.json")))
    assert_equal 2, index["failures"].size

    latest = File.join(Bulldogger.config.output_dir, "latest")
    assert File.symlink?(latest)
    assert_equal run_dir, File.readlink(latest)
  end

  # Forces File.symlink itself to fail (a permission error, one of the
  # SystemCallError subclasses the rescue names) by making the parent
  # directory read-only, rather than the "name already taken" case the
  # File.delete guard above it already handles. index.json is still
  # the source of truth, so finish must still succeed -- only "latest"
  # is allowed to go missing.
  def test_a_symlink_that_cannot_be_created_leaves_index_json_intact
    Bulldogger.start
    output_dir = Bulldogger.config.output_dir
    FileUtils.mkdir_p(output_dir)

    Bulldogger.record_failure(exception: trigger_raise, test: { framework: "minitest", id: "x", file: "f.rb", line: 1 })
    run_dir = Bulldogger.run_dir

    File.chmod(0o500, output_dir)
    begin
      Bulldogger.finish
    ensure
      File.chmod(0o755, output_dir)
    end

    assert File.exist?(File.join(run_dir, "index.json"))
    refute File.symlink?(File.join(output_dir, "latest"))
  end

  # attach_replay previously only wrote "replay_reproduced" for the
  # false case, so every reproduced-failure replay left the key
  # entirely absent (reading as JSON null to a caller) -- these two
  # cover both branches directly against a stub Replay, faster and
  # more precisely than driving a real child process end to end (see
  # test/acceptance/replay_load_path_test.rb for that).
  def test_replay_reproduced_true_is_written_when_the_child_reproduces_the_failure
    trace_path = File.join(Bulldogger.config.output_dir, "trace-001.jsonl")
    FileUtils.mkdir_p(File.dirname(trace_path))
    File.write(trace_path, "")
    evidence = evidence_with_replay(StubReplay.new(path: trace_path, reproduced: true))

    data = JSON.parse(File.read(evidence.record_failure(exception: trigger_raise, test: minimal_test)))

    assert_equal trace_path, data["replay"]
    assert_equal true, data["replay_reproduced"]
  end

  def test_replay_reproduced_false_is_written_and_no_replay_path_is_named_when_the_trace_is_missing
    evidence = evidence_with_replay(StubReplay.new(path: nil, reproduced: false))

    data = JSON.parse(File.read(evidence.record_failure(exception: trigger_raise, test: minimal_test)))

    assert_equal false, data["replay_reproduced"]
    refute data.key?("replay")
  end

  private

  StubReplay = Struct.new(:path, :reproduced, keyword_init: true) do
    def call(test:, run_dir:, frames:)
      { path: path, reproduced: reproduced }
    end
  end

  def evidence_with_replay(replay)
    Bulldogger::Evidence.new(
      config: Bulldogger.config,
      run: Bulldogger::Run.new(config: Bulldogger.config),
      capture: Bulldogger::Capture.new(config: Bulldogger.config),
      replay: replay
    )
  end

  def minimal_test
    { framework: "minitest", id: "x", file: "f.rb", line: 1 }
  end

  def trigger_raise
    raise "boom"
  rescue RuntimeError => e
    e
  end

  def trigger_huge_message
    raise "a" * 6000
  rescue RuntimeError => e
    e
  end

  class BrokenClassName < StandardError
    def self.name
      raise "no name for you"
    end
  end

  def trigger_broken_class_name
    raise BrokenClassName, "boom"
  rescue BrokenClassName => e
    e
  end
end
