# frozen_string_literal: true

require "fileutils"
require "json"

module Bulldogger
  # Owns the on-disk run directory: its lazy creation, evidence file
  # sequence numbers, and the index.json/latest written at the end.
  #
  # The directory is created lazily, on first use, not at
  # construction. A fully green test suite must never touch the
  # filesystem -- that is what "costs nothing while tests are green"
  # means in practice -- so nothing here may mkdir until a caller
  # actually asks for a path to write to.
  class Run
    def initialize(config:)
      @config = config
      @dir = nil
      @sequence = 0
      @failures = []
      @finished = false
      @mutex = Mutex.new
    end

    def dir
      @mutex.synchronize { ensure_dir }
    end

    def next_path(slug)
      @mutex.synchronize do
        ensure_dir
        @sequence += 1
        File.join(@dir, format("%03d-%s.json", @sequence, slug))
      end
    end

    def record(path, test:, exception_summary:)
      @mutex.synchronize do
        @failures << {
          "path" => File.basename(path),
          "test" => test,
          "exception" => exception_summary
        }
      end
    end

    def finish
      @mutex.synchronize do
        return if @finished

        @finished = true
        # No @dir means record was never called: a green run. Writing
        # an index for zero failures would create the very directory
        # the zero-cost-when-green claim says must not exist.
        return unless @dir

        write_index
        write_latest_symlink
      end
    end

    private

    def ensure_dir
      return @dir if @dir

      @dir = File.join(base_output_dir, run_dir_name)
      FileUtils.mkdir_p(@dir)
      @dir
    end

    def base_output_dir
      path = @config.output_dir
      File.absolute_path?(path) ? path : File.join(Dir.pwd, path)
    end

    def run_dir_name
      "run-#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{Process.pid}"
    end

    def write_index
      index = {
        "schema_version" => 1,
        "run_dir" => @dir,
        "failures" => @failures
      }
      File.write(File.join(@dir, "index.json"), "#{JSON.pretty_generate(index)}\n")
    end

    def write_latest_symlink
      link_path = File.join(base_output_dir, "latest")
      File.delete(link_path) if File.symlink?(link_path) || File.exist?(link_path)
      File.symlink(@dir, link_path)
    rescue SystemCallError, NotImplementedError
      # Not every filesystem supports symlinks. index.json and the
      # evidence files are the source of truth; "latest" is a
      # convenience an agent can lose without losing any evidence.
      nil
    end
  end
end
