# frozen_string_literal: true

require "bulldogger/minitest"
require "minitest/autorun"

class FltFixtureTest < Minitest::Test
  def branchy(input, password)
    total = input
    [2].each do |increment|
      block_value = total + increment
      total = block_value
    end
    label = total > 2 ? "large" : "small"
    [total, label, password]
  end

  def repeated(value)
    result = value * 2
    result
  end

  def loops
    values = []
    index = 0
    while index < 4
      values << index
      index += 1
    end
    values
  end

  def each_loop
    total = 0
    [1, 2, 3, 4].each do |value|
      total += value
    end
    total
  end

  def nested_loops
    pairs = []
    [1, 2, 3].each do |outer|
      [1, 2, 3, 4].each do |inner|
        pairs << [outer, inner]
      end
    end
    pairs
  end

  def test_trace_targets
    assert_equal [3, "large", "hidden"], branchy(1, "hidden")
    assert_equal 4, repeated(2)
    assert_equal 18, repeated(9)
    assert_equal [0, 1, 2, 3], loops
    assert_equal 10, each_loop
    assert_equal 12, nested_loops.length
  end
end
