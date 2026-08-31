# frozen_string_literal: true

module Bulldogger
  # Builds a child environment that loads one collector.
  # Each command remains responsible for its collector-specific variables.
  module CollectorEnvironment
    module_function

    def build(collector_name, variables)
      collector = File.expand_path(collector_name, __dir__)
      option = "-r#{collector}"
      rubyopt = ENV["RUBYOPT"]
      variables.merge("RUBYOPT" => rubyopt.nil? || rubyopt.empty? ? option : "#{rubyopt} #{option}")
    end
  end
end
