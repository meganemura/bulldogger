# frozen_string_literal: true

require "digest"
require "open3"

module Bulldogger
  # Reads the Git marker that identifies one run's source state.
  # Evidence storage and marker comparison stay outside this module.
  module CodeState
    module_function

    def capture(directory = Dir.pwd)
      sha, sha_status = git(directory, "rev-parse", "HEAD")
      return null_state unless sha_status.success?

      status, status_status = git(directory, "status", "--porcelain")
      return null_state unless status_status.success?

      {
        "git_sha" => sha.strip,
        "dirty_digest" => status.empty? ? "clean" : Digest::SHA256.hexdigest(status)
      }
    rescue Errno::ENOENT
      null_state
    end

    def git(directory, *arguments)
      stdout, _stderr, status = Open3.capture3("git", "-C", directory, *arguments)
      [stdout, status]
    end
    private_class_method :git

    def null_state
      { "git_sha" => nil, "dirty_digest" => nil }
    end
    private_class_method :null_state
  end
end
