# frozen_string_literal: true
# rbs_inline: enabled

module Bulldogger
  module Probe
    # One resolved probe target: the label the caller wrote
    # ("Klass#method" / "Klass.method") paired with the UnboundMethod
    # TracePoint#enable(target:) actually needs. Kept as a plain value
    # object so Session and Writer never re-derive the label from the
    # method (an UnboundMethod alone can't tell instance and singleton
    # spelling apart) or re-run constant/method lookup after start.
    Target = Struct.new(
      :label, #: String
      :unbound_method #: UnboundMethod
    )
  end
end
