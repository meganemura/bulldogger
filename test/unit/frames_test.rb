# frozen_string_literal: true

require "test_helper"
require "bulldogger/frames"

# seed_from is private_class_method + module_function, called only
# from Frames.append_envelope in production. Every acceptance run
# passes a real integer seed; this test reaches the one path those
# runs never do -- a --seed value that Integer() cannot parse.
class FramesTest < Minitest::Test
  def test_seed_from_returns_nil_for_an_unparseable_seed_value
    assert_nil Bulldogger::Frames.send(:seed_from, ["ruby", "-Itest", "app_test.rb", "--seed", "not-a-number"])
  end
end
