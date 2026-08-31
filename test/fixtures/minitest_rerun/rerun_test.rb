# frozen_string_literal: true

require "bulldogger/minitest"
require "minitest/autorun"

class RerunTest < Minitest::Test
  define_method(:'test_: when logged in should redirect to "the index". ') do
    begin
      raise "rescued marker"
    rescue RuntimeError
      nil
    end
    raise "rerun marker"
  end
end
