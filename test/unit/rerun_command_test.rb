# frozen_string_literal: true

require "test_helper"

class RerunCommandTest < Minitest::Test
  def test_minitest_command_uses_an_exact_anchored_method_pattern
    test = {
      framework: "minitest",
      id: "Example#test_: when logged in should redirect to \"the index\". ",
      file: "test/example test.rb",
      line: 12,
      seed: 123
    }

    command = Bulldogger::RerunCommand.build(test)

    assert_equal [
      "bundle", "exec", "ruby", "-Itest", "test/example test.rb", "-n",
      "/\\Atest_:\\ when\\ logged\\ in\\ should\\ redirect\\ to\\ \"the\\ index\"\\.\\ \\z/",
      "--seed", "123"
    ], Shellwords.split(command)
  end

  def test_rspec_command_uses_the_file_line_and_seed
    test = { framework: "rspec", id: "fails", file: "spec/example_spec.rb", line: 19, seed: 456 }

    assert_equal "bundle exec rspec spec/example_spec.rb:19 --seed 456", Bulldogger::RerunCommand.build(test)
  end

  def test_command_is_nil_when_a_required_value_is_missing
    assert_nil Bulldogger::RerunCommand.build(framework: "minitest", id: "X#test_x", file: "x.rb", seed: nil)
    assert_nil Bulldogger::RerunCommand.build(framework: "rspec", file: "x_spec.rb", line: nil, seed: 1)
    assert_nil Bulldogger::RerunCommand.build(framework: "unknown", id: "x", file: "x", line: 1, seed: 1)
  end
end
