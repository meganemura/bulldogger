# frozen_string_literal: true

# A real, small, failing suite: run as a child process by the
# acceptance suite, never required directly by it. Every local here
# (qty, rows, api_token) is seeded so the acceptance suite can check
# it appears in the written evidence, and that api_token is redacted.
require "bulldogger/minitest"
require "minitest/autorun"
require_relative "app"

class RedTest < ::Minitest::Test
  def test_assertion_failure
    qty = 3
    rows = [1, 2, 3]
    api_token = "sk-secret" # only needs to exist: the acceptance suite checks it is redacted in this frame's evidence
    assert_equal 4, qty + rows.sum, "seeded api_token: #{api_token.length} chars"
  end

  def test_deep_raise
    Order.total(qty: 3, rows: [1, 2, 3], api_token: "sk-secret")
  end
end
