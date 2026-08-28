# frozen_string_literal: true

require "test_helper"
require_relative "../fixtures/probe/target_app"

# Guards the offset argument to caller_locations inside the probe
# TracePoint hook (session.rb): a wrong offset does not raise, it
# silently returns a location one frame off (this library's own line,
# or a frame that exists but is the wrong one), so nothing but a
# direct test catches a wrong number here.
class ProbeCallerOffsetTest < Minitest::Test
  def test_caller_locations_2_1_names_the_same_line_as_caller_locations_2_3_first
    invoice = Billing::Invoice.new
    three_frame_first = nil
    one_frame = nil
    tp = TracePoint.new(:call) do |_t|
      # Computed in the same hook invocation, at the same frame depth
      # session.rb's own hook runs at, so this is a fair comparison of
      # the two offsets rather than two different call sites.
      three_frame_first = caller_locations(2, 3)&.first
      one_frame = caller_locations(2, 1)&.first
    end
    tp.enable(target: Billing::Invoice.instance_method(:amount))
    begin
      invoice.amount(1) # the call site both offsets must name
    ensure
      tp.disable
    end

    refute_nil three_frame_first
    refute_nil one_frame
    assert_equal three_frame_first.path, one_frame.path
    assert_equal three_frame_first.lineno, one_frame.lineno
  end
end
