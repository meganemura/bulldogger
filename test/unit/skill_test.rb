# frozen_string_literal: true

require "test_helper"
require "bulldogger/skill"
require "open3"
require "fileutils"

class SkillTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CLI = File.join(ROOT, "exe/bulldogger")

  def test_skill_path_is_absolute_and_contains_the_skill
    path = Bulldogger.skill_path

    assert File.absolute_path?(path)
    assert File.file?(File.join(path, "SKILL.md"))
  end

  def test_vendored_lib_without_skills_omits_the_evidence_key
    Dir.mktmpdir("bulldogger-without-skills-") do |root|
      assert_nil Bulldogger::Skill.file(root)
      FileUtils.cp_r(File.join(ROOT, "lib"), root)
      code = <<~'RUBY'
        require "bulldogger"
        require "json"
        Bulldogger.config.output_dir = ARGV.fetch(0)
        path = Bulldogger.record_failure(
          exception: RuntimeError.new("missing skill"),
          test: { framework: "test", id: "missing", file: "missing.rb", line: 1 }
        )
        puts JSON.parse(File.read(path)).key?("skill")
      RUBY
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-I#{File.join(root, "lib")}", "-e", code, File.join(root, "output")
      )

      assert status.success?, stderr
      assert_equal "false", stdout.strip
    end
  end

  def test_cli_prints_the_skill_path
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", CLI, "skill", "path", chdir: ROOT)

    assert status.success?, stderr
    assert_equal Bulldogger.skill_path, stdout.strip
  end

  def test_cli_prints_the_version_for_both_forms
    [["version"], ["--version"]].each do |arguments|
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", CLI, *arguments, chdir: ROOT)

      assert status.success?, stderr
      assert_equal Bulldogger::VERSION, stdout.strip
    end
  end

  def test_cli_rejects_an_unknown_command
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", CLI, "unknown", chdir: ROOT)

    refute status.success?
    assert_includes stderr, "Usage:"
  end
end
