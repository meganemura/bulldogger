# frozen_string_literal: true

require "shellwords"

module Bulldogger
  # Builds framework test selectors and complete shell rerun commands.
  # Replay execution and process management stay outside this module.
  module RerunCommand
    module_function

    def build(test)
      return nil unless test && test[:file] && test[:seed]

      arguments = case test[:framework]
                  when "minitest"
                    minitest_arguments(test)
                  when "rspec"
                    rspec_arguments(test)
                  end
      arguments && Shellwords.join(arguments)
    end

    def minitest_method(test)
      test[:id].to_s.split("#", 2)[1]
    end

    def rspec_location(test)
      "#{test[:file]}:#{test[:line]}" if test[:file] && test[:line]
    end

    def minitest_arguments(test)
      method_name = minitest_method(test)
      return nil unless method_name

      pattern = "/\\A#{Regexp.escape(method_name)}\\z/"
      ["bundle", "exec", "ruby", "-Itest", test[:file], "-n", pattern, "--seed", test[:seed].to_s]
    end
    private_class_method :minitest_arguments

    def rspec_arguments(test)
      location = rspec_location(test)
      return nil unless location

      ["bundle", "exec", "rspec", location, "--seed", test[:seed].to_s]
    end
    private_class_method :rspec_arguments
  end
end
