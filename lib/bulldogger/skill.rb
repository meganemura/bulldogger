# frozen_string_literal: true

module Bulldogger
  # Resolves the skill shipped beside the library. Evidence writers
  # decide where to place the resolved file in their own formats.
  module Skill
    ROOT = File.expand_path("../..", __dir__).freeze

    def self.path(root = ROOT)
      path = File.expand_path("skills/bulldogger", root)
      File.file?(File.join(path, "SKILL.md")) ? path : nil
    end

    def self.file(root = ROOT)
      skill_path = path(root)
      File.join(skill_path, "SKILL.md") if skill_path
    end
  end

  def self.skill_path
    Skill.path
  end
end
