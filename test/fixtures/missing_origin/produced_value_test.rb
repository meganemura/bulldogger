# frozen_string_literal: true

require "bulldogger/minitest"
require "minitest/autorun"
require_relative "app"

class ProducedValueTest < Minitest::Test
  def test_total_matches_the_expected_price
    value = Pricing.total(qty: 3)
    assert_equal 999, value
  end
end
