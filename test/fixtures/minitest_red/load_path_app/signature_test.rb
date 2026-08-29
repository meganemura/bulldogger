# frozen_string_literal: true

require "load_path_helper"

class SignatureTest < ::Minitest::Test
  # Deliberately wrong: Signature.accepts_arity?(1, 1) returns true, so
  # this always fails via assert_equal, once accepts_arity? has already
  # returned -- not via a raise, which the failure snapshot alone would
  # already be able to place without replay's help.
  def test_accepts_arity_rejects_a_count_equal_to_required
    assert_equal false, Signature.accepts_arity?(1, 1)
  end
end
