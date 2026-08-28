# frozen_string_literal: true

require "test_helper"

class CaptureTest < Minitest::Test
  def test_locals_and_frame_position_appear_in_the_snapshot
    Bulldogger.start

    exception, line = trigger_raise_with_locals
    snapshot = Bulldogger.snapshot_for(exception)
    frame0 = snapshot["frames"][0]

    assert_equal({ "value" => "3" }, frame0["locals"]["qty"])
    assert_equal({ "value" => "[1, 2, 3]" }, frame0["locals"]["rows"])
    assert_equal __FILE__, frame0["path"]
    assert_equal line, frame0["line"]
    assert_includes frame0["label"], "trigger_raise_with_locals"
  end

  def test_reraise_keeps_the_first_captures_frame
    Bulldogger.start

    exception, first_line = trigger_reraise
    snapshot = Bulldogger.snapshot_for(exception)

    assert_equal first_line, snapshot["frames"][0]["line"]
  end

  def test_hook_never_lets_an_exception_escape_into_the_app
    Bulldogger.start
    formatter = Bulldogger.send(:capture).instance_variable_get(:@formatter)
    def formatter.format(*)
      raise "formatter exploded"
    end

    message =
      begin
        raise "app error"
      rescue RuntimeError => e
        e.message
      end

    assert_equal "app error", message
  end

  def test_pending_ring_evicts_the_oldest_entries
    Bulldogger.config.max_pending = 2
    Bulldogger.start

    exceptions = Array.new(5) { |i| raise_numbered(i) }

    exceptions.first(3).each { |e| assert_nil Bulldogger.snapshot_for(e) }
    exceptions.last(2).each { |e| refute_nil Bulldogger.snapshot_for(e) }
  end

  private

  def trigger_raise_with_locals
    qty = 3
    rows = [1, 2, 3]
    [qty, rows] # read once so -w doesn't call these unused; capture reads them via binding, not this line
    line = __LINE__ + 1
    raise ArgumentError, "boom"
  rescue ArgumentError => e
    [e, line]
  end

  def trigger_reraise
    begin
      line = __LINE__ + 1
      raise "boom"
    rescue RuntimeError => e
      begin
        raise e
      rescue RuntimeError => e2
        return [e2, line]
      end
    end
  end

  def raise_numbered(i)
    raise "boom #{i}"
  rescue RuntimeError => e
    e
  end
end
