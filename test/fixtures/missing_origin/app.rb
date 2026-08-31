# frozen_string_literal: true

# A method that returns a value and raises nothing of its own. Its
# frame is gone from the stack by the time a later assertion on that
# value fails -- the shape a snapshot alone cannot answer, and the
# frames verb must reach through a rerun instead.
module Pricing
  def self.total(qty:)
    qty * 2
  end
end
