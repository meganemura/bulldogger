# frozen_string_literal: true

require "bulldogger/rspec"

RSpec.describe "rerun" do
  it "reproduces the selected failure" do
    begin
      raise "rescued marker"
    rescue RuntimeError
      nil
    end
    raise "rerun marker"
  end
end
