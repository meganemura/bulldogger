# frozen_string_literal: true

require "rbconfig"

module Bulldogger
  # Classifies frames by their source path for failure output guidance.
  # It does not decide what a caller does with that classification.
  module ApplicationFrames
    module_function

    def available?(test_file, frames)
      return false unless test_file && frames.respond_to?(:any?)

      test_path = File.expand_path(test_file)
      # A gem can raise while an application caller remains on the stack.
      # That caller can hold the values, so classification checks every frame.
      frames.any? do |frame|
        raw_path = frame["path"].to_s
        next false if raw_path.empty?

        path = File.expand_path(raw_path)
        path != test_path && !library_path?(path)
      end
    end

    def library_path?(path)
      library_paths.any? { |prefix| path.start_with?(prefix) }
    end

    def library_paths
      # A vendored bundle can sit inside the project directory. Gem.path still
      # identifies it, so project-directory classification would be incorrect.
      Gem.path + RbConfig::CONFIG.values_at("rubylibdir", "sitelibdir").compact
    end
  end
end
