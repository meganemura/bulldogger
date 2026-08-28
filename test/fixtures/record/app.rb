# frozen_string_literal: true

# A method in its own file, called by the fixture script: the
# acceptance case is a class-method call from outside the file that
# defines it, so the recorded "method" label has to name the real
# owner (Billing), not wherever the call happened to originate.
module Billing
  def self.total(qty:, price:, api_token:)
    qty * price
  end

  def self.total!(qty:)
    raise ArgumentError, "qty must be positive" if qty <= 0

    qty
  end
end
