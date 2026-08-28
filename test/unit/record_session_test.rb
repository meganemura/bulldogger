# frozen_string_literal: true

require "test_helper"
require "bulldogger/record"
require_relative "../support/real_trace_point"
require_relative "../fixtures/probe/target_app"

# Record::Session's #handle/#dispatch/every on_*/every build_*_event
# are only ever called from inside its own global :call/:return/
# :raise/:rescue TracePoint hook in production, which stdlib Coverage
# cannot reliably observe (see test/unit/tracepoint_coverage_blind_spot_test.rb). record_events_test.rb
# already proves this code's *behavior* through that real hook; these
# tests call the same private methods directly instead, with doubles
# built from real calls/raises, so the lines themselves are visible to
# Coverage too.
class RecordSessionTest < Minitest::Test
  FakeSink = Struct.new(:events) do
    def initialize
      super([])
    end

    def write_event(event)
      events << event
    end
  end

  def setup
    super
    @sink = FakeSink.new
    @session = new_session
  end

  def test_handle_writes_a_call_event_for_a_real_call
    call_tp, = capture(:amount) { Billing::Invoice.new.amount(4) }

    @session.send(:handle, call_tp)

    assert_equal 1, @sink.events.size
    assert_equal "call", @sink.events.first["event"]
  end

  # A global TracePoint is live for the entire process from #enable
  # onward -- this filter is what keeps this library's own frames
  # (Redactor, in this real call) out of the trace. Targets a real
  # method inside lib/bulldogger so the tp's own #path is genuinely
  # under this library's tree, not a fabricated value.
  def test_handle_filters_out_a_call_whose_path_is_inside_this_librarys_own_lib_directory
    redactor = Bulldogger::Redactor.new([])
    call_tp, = capture_method(Bulldogger::Redactor.instance_method(:redact_name?)) { redactor.redact_name?("x") }

    @session.send(:handle, call_tp)

    assert_empty @sink.events
  end

  def test_handle_skips_once_stopping_is_set
    call_tp, = capture(:amount) { Billing::Invoice.new.amount(1) }
    @session.instance_variable_set(:@stopping, true)

    @session.send(:handle, call_tp)

    assert_empty @sink.events
  end

  def test_handle_skips_when_this_thread_is_already_inside_its_own_handler
    call_tp, = capture(:amount) { Billing::Invoice.new.amount(1) }
    reentrant_key = @session.instance_variable_get(:@reentrant_key)
    Thread.current[reentrant_key] = true

    @session.send(:handle, call_tp)

    assert_empty @sink.events
  ensure
    Thread.current[reentrant_key] = nil
  end

  # Same rule as Capture's :raise hook: a recorder must never be the
  # reason the traced code fails.
  def test_handle_swallows_its_own_internal_failure
    call_tp, = capture(:amount) { Billing::Invoice.new.amount(1) }
    def @session.dispatch(_tp)
      raise "dispatch exploded"
    end

    @session.send(:handle, call_tp)
  end

  def test_dispatch_on_call_writes_actual_arguments_including_a_defaulted_keyword
    call_tp, = capture(:amount) { Billing::Invoice.new.amount(4) }

    @session.send(:dispatch, call_tp)

    event = @sink.events.first
    assert_equal "Billing::Invoice#amount", event["method"]
    assert_equal({ "value" => "4" }, event["args"]["mult"])
    assert_equal({ "value" => "nil" }, event["args"]["discount"])
  end

  def test_dispatch_on_call_redacts_a_secret_named_argument
    call_tp, = capture(:charge) { Billing::Invoice.new.charge("s3cr3t") }

    @session.send(:dispatch, call_tp)

    args = @sink.events.first["args"]
    assert_equal({ "redacted" => true, "reason" => "name" }, args["api_token"])
  end

  def test_dispatch_on_call_for_a_singleton_method_labels_it_with_a_dot
    call_tp, = capture_method(Order.method(:total).unbind) { Order.total(3) }

    @session.send(:dispatch, call_tp)

    assert_equal "Order.total", @sink.events.first["method"]
  end

  def test_dispatch_on_return_writes_the_formatted_return_value
    call_tp, return_tp = capture(:amount) { Billing::Invoice.new.amount(3) }
    @session.send(:dispatch, call_tp)
    @sink.events.clear

    @session.send(:dispatch, return_tp)

    event = @sink.events.first
    assert_equal "return", event["event"]
    assert_equal({ "value" => "30" }, event["return"])
    refute event.key?("raised")
  end

  # raised: true's whole reason to exist -- a raise anywhere during the
  # call's lifetime moves the shared counter; :return reads the delta
  # against the checkpoint on_call pushed, not tp.return_value (which
  # would misreport the exit as a nil return).
  def test_dispatch_on_return_after_a_raise_marks_raised_true_and_omits_return
    call_tp, return_tp = capture(:blows_up) do
      begin
        Billing::Invoice.new.blows_up
      rescue ArgumentError
        nil
      end
    end
    raise_tp = Bulldogger::TestSupport.capture_raise { raise "unrelated raise" }
    @session.send(:dispatch, call_tp)
    @session.send(:dispatch, raise_tp)
    @sink.events.clear

    @session.send(:dispatch, return_tp)

    event = @sink.events.first
    assert_equal true, event["raised"]
    refute event.key?("return")
  end

  def test_dispatch_on_raise_writes_the_exception_class_and_message
    raise_tp = Bulldogger::TestSupport.capture_raise { raise "boom" }

    @session.send(:dispatch, raise_tp)

    event = @sink.events.first
    assert_equal "raise", event["event"]
    assert_equal "RuntimeError", event["exception"]["class"]
    assert_equal "boom", event["exception"]["message"]
  end

  def test_dispatch_on_raise_truncates_a_huge_message_and_marks_the_cut
    huge_message = "x" * ((Bulldogger.config.max_value_length * 5) + 50)
    raise_tp = Bulldogger::TestSupport.capture_raise { raise huge_message }

    @session.send(:dispatch, raise_tp)

    section = @sink.events.first["exception"]
    assert section["message_truncated"]
    assert section["message_original_length"]
  end

  # exception_class_name's own rescue: an exception class whose own
  # .name raises must not take the whole recorder down with it.
  def test_dispatch_on_raise_falls_back_to_object_when_the_exception_class_name_raises
    raise_tp = Bulldogger::TestSupport.capture_raise { raise BrokenClassName, "boom" }

    @session.send(:dispatch, raise_tp)

    assert_equal "Object", @sink.events.first["exception"]["class"]
  end

  # Not written to the trace -- :rescue only feeds the -1 half of the
  # raise/rescue delta #on_return reads (contract-verbs.md). tp is
  # ignored entirely by on_rescue, so a minimal double with just the
  # event symbol is faithful; nothing under test reads any other field
  # of it.
  def test_dispatch_on_rescue_decrements_the_counter_without_writing_anything
    before = @session.instance_variable_get(:@raise_rescue_counter)

    @session.send(:dispatch, Bulldogger::TestSupport::Double.new(event: :rescue))

    assert_equal before - 1, @session.instance_variable_get(:@raise_rescue_counter)
    assert_empty @sink.events
  end

  # attached_object raises TypeError for a singleton class with no
  # attached object (contract-verbs.md's own documented edge case);
  # method_label's contract only needs #singleton_class?/
  # #attached_object from defined_class, so a minimal double built to
  # exhibit exactly that failure exercises the real rescue without
  # needing an exotic real Ruby object that happens to behave this way.
  def test_method_label_falls_back_to_method_id_when_attached_object_raises
    poisoned_singleton = Object.new
    def poisoned_singleton.singleton_class?
      true
    end

    def poisoned_singleton.attached_object
      raise TypeError, "no attached object"
    end
    tp = Bulldogger::TestSupport::Double.new(event: :call, defined_class: poisoned_singleton, method_id: :mystery)

    assert_equal "mystery", @session.send(:method_label, tp)
  end

  private

  class BrokenClassName < StandardError
    def self.name
      raise "no name for you"
    end
  end

  def capture(method_name, &block)
    capture_method(Billing::Invoice.instance_method(method_name), &block)
  end

  def capture_method(unbound_method, &block)
    Bulldogger::TestSupport.capture_call_and_return(unbound_method, &block)
  end

  # Session's own TracePoint fires globally the instant it is built
  # (see the class's own comment on that); it is disabled immediately
  # so it never observes anything a test does with its own, separate
  # capture_call_and_return TracePoint -- this file tests the session's
  # methods directly, not its live hook.
  #
  # @stopping is set around the disable call the same way #stop itself
  # does, and for the same reason (#handle's own comment): #disable is
  # a Ruby-level method, so calling it while the trace point is still
  # enabled fires one last :call event through this very handler,
  # right back into @sink, before the disable takes effect -- confirmed
  # directly while writing this file (an un-guarded disable leaked a
  # "TracePoint#disable" call event into every test below). Reset to
  # false again afterward so the guard does not also swallow this
  # file's own direct #handle/#dispatch calls.
  def new_session
    session = Bulldogger::Record::Session.new(config: Bulldogger.config, run_dir: nil, sink: @sink)
    session.instance_variable_set(:@stopping, true)
    session.instance_variable_get(:@trace_point).disable
    session.instance_variable_set(:@stopping, false)
    # A second-or-later Record::Session built in this same process
    # observes its own @trace_point.enable call returning, as a
    # {"path"=>"<internal:trace_point>", "method"=>"TracePoint#enable"}
    # event: a pre-existing gap in SKIP_PATH_PREFIX filtering (it only
    # covers this library's own lib/ paths, not Ruby's own
    # <internal:trace_point> boot file), unrelated to anything this
    # file tests. Confirmed this is not specific to this file's own
    # sink: seam -- it reproduces the same way through
    # Bulldogger::Record.run itself on the 2nd+ call in one process.
    # Draining it here keeps every test below starting from a clean
    # sink; the lib/ fix for the underlying gap is out of this task's
    # scope (reported separately).
    @sink.events.clear
    session
  end
end
