# frozen_string_literal: true

# A real, small, fully passing suite: the acceptance suite runs this
# as a child process and checks that no run directory is created --
# the zero-cost-when-green claim demonstrated by execution, not by
# reading the source.
require_relative "spec_helper"

RSpec.describe "Green" do
  it "passes" do
    expect(1 + 1).to eq(2)
  end
end
