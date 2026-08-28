# frozen_string_literal: true

# Run as a child process by test/acceptance/record_integration_test.rb.
# Prints the absolute trace path on its own line -- the same
# stdout-names-the-evidence-path pattern the minitest/rspec fixtures
# use for failure evidence -- then the acceptance test reads that path
# and the JSONL file itself.
require "bulldogger/record"
require_relative "app"

path = Bulldogger::Record.run do
  Billing.total(qty: 3, price: 4, api_token: "sk-secret")
  begin
    Billing.total!(qty: -1)
  rescue ArgumentError
    nil
  end
end

puts "BULLDOGGER_TRACE: #{path}"
