# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "shellwords"

class CodeStateTest < Minitest::Test
  def test_clean_repository_has_a_sha_and_clean_digest
    Dir.mktmpdir("bulldogger-code-state-") do |dir|
      git(dir, "init", "-q")
      git(dir, "config", "user.email", "test@example.com")
      git(dir, "config", "user.name", "Test")
      File.write(File.join(dir, "tracked.txt"), "one\n")
      git(dir, "add", "tracked.txt")
      git(dir, "commit", "-qm", "initial")

      state = Bulldogger::CodeState.capture(dir)

      assert_match(/\A[0-9a-f]{40}\z/, state["git_sha"])
      assert_equal "clean", state["dirty_digest"]
    end
  end

  def test_dirty_repository_hashes_porcelain_status
    Dir.mktmpdir("bulldogger-code-state-") do |dir|
      git(dir, "init", "-q")
      git(dir, "config", "user.email", "test@example.com")
      git(dir, "config", "user.name", "Test")
      File.write(File.join(dir, "tracked.txt"), "one\n")
      git(dir, "add", "tracked.txt")
      git(dir, "commit", "-qm", "initial")
      File.write(File.join(dir, "new.txt"), "new\n")
      status = `git -C #{Shellwords.escape(dir)} status --porcelain`

      assert_equal Digest::SHA256.hexdigest(status), Bulldogger::CodeState.capture(dir)["dirty_digest"]
    end
  end

  def test_directory_without_git_metadata_has_null_values
    Dir.mktmpdir("bulldogger-code-state-") do |dir|
      assert_equal({ "git_sha" => nil, "dirty_digest" => nil }, Bulldogger::CodeState.capture(dir))
    end
  end

  private

  def git(dir, *args)
    system("git", "-C", dir, *args, out: File::NULL, err: File::NULL) || raise("git failed")
  end
end
