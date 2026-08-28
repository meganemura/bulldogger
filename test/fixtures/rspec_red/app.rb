# frozen_string_literal: true

# A method in its own file, called by the spec file: the acceptance
# suite's primary case is a raise from deep in app code, not from the
# example itself, so evidence must reach this frame and not just the
# caller's.
module Order
  def self.total(qty:, rows:, api_token:)
    raise ArgumentError, "expected #{qty} to equal the sum of #{rows.inspect}"
  end
end
