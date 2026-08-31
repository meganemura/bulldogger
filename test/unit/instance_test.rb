# frozen_string_literal: true

require "test_helper"

class InstanceTest < Minitest::Test
  def test_instance_owns_config_and_runtime_state
    first = Bulldogger::Instance.new
    second = Bulldogger::Instance.new

    refute_same first.config, second.config
    first.configure { |config| config.max_frames = 3 }
    assert_equal 3, first.config.max_frames
    assert_equal 20, second.config.max_frames
  end

  def test_instance_accepts_a_config
    config = Bulldogger::Config.new
    instance = Bulldogger::Instance.new(config: config)

    assert_same config, instance.config
  end

  def test_stopping_one_instance_does_not_stop_another
    outer = Bulldogger::Instance.new
    inner = Bulldogger::Instance.new
    outer.start
    inner.start

    first_error = raise_and_return("first")
    inner.stop
    second_error = raise_and_return("second")

    refute_nil outer.snapshot_for(first_error)
    refute_nil outer.snapshot_for(second_error)
    refute inner.running?
    assert outer.running?
  ensure
    outer&.stop
    inner&.stop
  end

  def test_facade_delegates_to_the_default_instance
    default = Bulldogger.default

    assert_same default.config, Bulldogger.config
    assert_same Bulldogger, Bulldogger.configure { |config| config.max_frames = 4 }
    assert_equal 4, default.config.max_frames
    assert_same Bulldogger, Bulldogger.start
    assert Bulldogger.running?
    assert_same Bulldogger, Bulldogger.stop
    refute default.running?
  end

  def test_instance_probe_and_comparison_entry_points
    instance = Bulldogger::Instance.new
    instance.config.output_dir = Dir.mktmpdir("bulldogger-instance-")

    probe_path = instance.probe("InstanceTest#probe_target") { probe_target(1) }

    assert File.exist?(probe_path)
    assert_equal({ "identical" => true, "differences" => [] }, instance.probe_compare(probe_path, probe_path))
  end

  private

  def raise_and_return(message)
    raise message
  rescue RuntimeError => error
    error
  end

  def probe_target(value)
    value * 2
  end
end
