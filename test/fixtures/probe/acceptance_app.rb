# frozen_string_literal: true

# Runs as a real child process under bundle exec (see
# BulldoggerAcceptanceHelper#run_fixture): a small, real app, probed
# the same way an adopter would probe their own code, with a seeded
# argument, return value, and caller for the acceptance test to find
# in the written evidence file.

require "bulldogger"
require_relative "target_app"

invoice = Billing::Invoice.new

def call_amount(invoice, mult, discount: nil)
  invoice.amount(mult, discount: discount)
end

path = Bulldogger.probe("Billing::Invoice#amount", "Billing::Invoice#charge") do
  call_amount(invoice, 3)
  call_amount(invoice, 5, discount: 2)
  invoice.charge("supersecret")
end

puts "probe evidence: #{path}"
