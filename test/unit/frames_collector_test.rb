# frozen_string_literal: true

require_relative "../test_helper"
require "bulldogger/frames_collector"

class FramesCollectorTest < Minitest::Test
  def test_normalizes_the_complete_compiled_template_numeric_tail
    first = "_app_views_x_html_erb__4423017493750537167_15192"
    second = "_app_views_x_html_erb___2751381140246492290_99999"

    assert_equal Bulldogger::FramesMethod.normalize(first), Bulldogger::FramesMethod.normalize(second)
    assert_equal "push__2", Bulldogger::FramesMethod.normalize("push__2")
  end
end
