# frozen_string_literal: true

require "test_helper"
require "bulldogger/integrations/minitest"
require "bulldogger/integrations/rspec"

class IntegrationInstanceTest < Minitest::Test
  def setup
    super
    @previous_minitest_instance = Bulldogger::Minitest.instance_variable_get(:@instance)
    @previous_rspec_instance = Bulldogger::RSpec.instance_variable_get(:@instance)
    Bulldogger::Minitest.instance_variable_set(:@instance, nil)
    Bulldogger::RSpec.instance_variable_set(:@instance, nil)
  end

  def teardown
    Bulldogger::Minitest.instance_variable_set(:@instance, @previous_minitest_instance)
    Bulldogger::RSpec.instance_variable_set(:@instance, @previous_rspec_instance)
    super
  end

  def test_integrations_use_the_default_instance_when_unset
    assert_same Bulldogger.default, Bulldogger::Minitest.instance
    assert_same Bulldogger.default, Bulldogger::RSpec.instance
  end

  def test_integrations_use_an_assigned_instance
    minitest_instance = Bulldogger::Instance.new
    rspec_instance = Bulldogger::Instance.new

    Bulldogger::Minitest.instance = minitest_instance
    Bulldogger::RSpec.instance = rspec_instance

    assert_same minitest_instance, Bulldogger::Minitest.instance
    assert_same rspec_instance, Bulldogger::RSpec.instance
  end
end
