# frozen_string_literal: true

# A real, small, failing suite: run as a child process by the
# acceptance suite, never required directly by it. Every local here
# (qty, rows, api_token) is seeded so the acceptance suite can check
# it appears in the written evidence, and that api_token is redacted.
require_relative "spec_helper"
require_relative "app"

RSpec.describe "Order" do
  it "computes the total" do
    qty = 3
    rows = [1, 2, 3]
    api_token = "sk-secret" # only needs to exist: the acceptance suite checks it is redacted in this frame's evidence
    expect(qty + rows.sum + api_token.length).to eq(4)
  end

  it "raises deep in app code" do
    Order.total(qty: 3, rows: [1, 2, 3], api_token: "sk-secret")
  end
end
