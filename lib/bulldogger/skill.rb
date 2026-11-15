# frozen_string_literal: true
# rbs_inline: enabled

module Bulldogger
  # Resolves the skill for all evidence writers and the CLI. It does not
  # install the skill or decide how a caller presents the resolved path.
  # One resolver keeps every evidence format and the CLI in agreement.
  module Skill
    ROOT = File.expand_path("../..", __dir__.to_s).freeze

    #: (?String root) -> String?
    def self.path(root = ROOT)
      path = File.expand_path("skills/bulldogger", root)
      # A vendored lib/ tree can omit the skill. A missing path costs the
      # reader less than a path that points to a file that does not exist.
      File.file?(File.join(path, "SKILL.md")) ? path : nil
    end

    #: (?String root) -> String?
    def self.file(root = ROOT)
      skill_path = path(root)
      File.join(skill_path, "SKILL.md") if skill_path
    end
  end

  #: () -> String?
  def self.skill_path
    Skill.path
  end
end
