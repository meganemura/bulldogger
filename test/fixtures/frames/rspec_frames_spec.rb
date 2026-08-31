# frozen_string_literal: true

require "bulldogger/rspec"

def rspec_target
  :seen
end

RSpec.describe "frames" do
  it "records the target" do
    expect(rspec_target).to eq(:seen)
  end
end
