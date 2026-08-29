# frozen_string_literal: true

require "load_path_spec_helper"

RSpec.describe "Signature" do
  # Deliberately wrong: Signature.accepts_arity?(1, 1) returns true, so
  # this always fails via the `eq` matcher, once accepts_arity? has
  # already returned -- not via a raise, which the failure snapshot
  # alone would already be able to place without replay's help.
  it "rejects a count equal to required" do
    expect(Signature.accepts_arity?(1, 1)).to eq(false)
  end
end
