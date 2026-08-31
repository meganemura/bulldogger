# frozen_string_literal: true

require "bulldogger/minitest"
require "minitest/autorun"

class ExecFixtureTest < Minitest::Test
  def threshold(value)
    result = value
    result
  end

  def loop_values
    values = []
    3.times do |index|
      current = index + 1
      values << current
    end
    values
  end

  def stable_value
    value = 7
    value
  end

  def secret_value
    secret = { password: "hidden", visible: "shown" }
    secret
  end

  def test_injection_can_change_the_outcome
    assert_equal 10, threshold(4)
  end

  def test_loop_values
    assert_equal [1, 2, 3], loop_values
  end

  def test_statement_exception_does_not_change_the_outcome
    assert_equal 7, stable_value
  end

  def test_redaction
    assert_equal "shown", secret_value.fetch(:visible)
  end
end
