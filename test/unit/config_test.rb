# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  def test_bulldogger_disable_env_var_disables
    with_env("BULLDOGGER_DISABLE" => "1", "BULLDOGGER_DISABLED" => nil) do
      assert_equal false, Bulldogger::Config.new.enabled
    end
  end

  # BULLDOGGER_DISABLE is the documented name, but a switch that only
  # answers to that exact spelling and silently ignores the adjective
  # form a user actually types is a switch that fails quietly: the
  # user believes they turned it off and evidence keeps writing.
  def test_bulldogger_disabled_env_var_is_accepted_as_an_alias
    with_env("BULLDOGGER_DISABLE" => nil, "BULLDOGGER_DISABLED" => "1") do
      assert_equal false, Bulldogger::Config.new.enabled
    end
  end

  def test_bulldogger_frame_source_env_var_selects_capture_frames
    with_env("BULLDOGGER_FRAME_SOURCE" => "capture_frames") do
      assert_equal :capture_frames, Bulldogger::Config.new.frame_source
    end
  end

  def test_bulldogger_frame_source_env_var_selects_degraded
    with_env("BULLDOGGER_FRAME_SOURCE" => "degraded") do
      assert_equal :degraded, Bulldogger::Config.new.frame_source
    end
  end

  def test_enabled_by_default_with_neither_env_var_set
    with_env("BULLDOGGER_DISABLE" => nil, "BULLDOGGER_DISABLED" => nil) do
      assert_equal true, Bulldogger::Config.new.enabled
    end
  end

  def test_bulldogger_configure_yields_the_shared_config_and_returns_bulldogger
    result = Bulldogger.configure { |c| c.max_frames = 3 }

    assert_equal 3, Bulldogger.config.max_frames
    assert_equal Bulldogger, result
  end

  private

  # Config reads ENV once, in #initialize, so each case here needs its
  # own Config.new inside the stubbed environment rather than mutating
  # the process-global Bulldogger.config (which test_helper already
  # resets per test, but only after ENV has been read).
  def with_env(vars)
    original = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
