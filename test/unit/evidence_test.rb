# frozen_string_literal: true

require "test_helper"
require "json"

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
    assert data["frames_unavailable_reason"]
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

  private

  def trigger_raise
    raise "boom"
  rescue RuntimeError => e
    e
  end
end
