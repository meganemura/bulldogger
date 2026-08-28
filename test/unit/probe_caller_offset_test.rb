# frozen_string_literal: true

require "test_helper"
require_relative "../fixtures/probe/target_app"

# Guards the offset argument to caller_locations inside the probe
# TracePoint hook (session.rb): a wrong offset does not raise, it
# silently returns a location one frame off (this library's own line,
# or a frame that exists but is the wrong one), so nothing but a
# direct test catches a wrong number here.
#
# session.rb's block delegates to a named method (dispatch), and
# caller_locations runs inside that method's own body, not inside the
# block itself -- this test mirrors that exact shape (a TracePoint
# block that calls one named method, whose own body calls
# caller_locations) and checks the result against a known call site,
# rather than the pre-refactor test's approach of comparing two
# offsets against each other at bare-block depth.
class ProbeCallerOffsetTest < Minitest::Test
  def test_caller_locations_3_1_from_the_delegated_method_names_the_app_call_site
    invoice = Billing::Invoice.new
    @captured = nil
    tp = TracePoint.new(:call) { |_t| dispatch_like_session_does }
    tp.enable(target: Billing::Invoice.instance_method(:amount))
    begin
      line = __LINE__ + 1
      invoice.amount(1) # the call site the offset must name
    ensure
      tp.disable
    end

    refute_nil @captured
    assert_equal __FILE__, @captured.path
    assert_equal line, @captured.lineno
  end

  private

  # Mirrors session.rb's own shape exactly: TracePoint.new's block
  # calls this one named method (not a further yield), and this
  # method's own body -- not the block -- is where caller_locations(3,
  # 1) runs, the same depth session.rb's dispatch runs at.
  def dispatch_like_session_does
    @captured = caller_locations(3, 1)&.first
  end
end
