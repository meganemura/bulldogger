# frozen_string_literal: true

require "open3"
require "json"
require "tmpdir"

# Shared machinery for the acceptance suite: every check here runs a
# fixture as a real child process under bundle exec (the same
# toolchain a real adopter runs), then reads its stdout and the files
# it wrote. Bulldogger itself is never required in this process --
# only fixtures load bulldogger/minitest or bulldogger/rspec, so the
# harness's own run stays outside anything it is trying to measure.
module BulldoggerAcceptanceHelper
  ROOT = File.expand_path("../..", __dir__)
  # Anchored to an absolute path (leading /): the printed line is
  # documented to always name an absolute path (an agent may run from
  # any directory), so a relative match here would let a regression on
  # that point go unchecked.
  EVIDENCE_LINE = %r{bulldogger evidence: (/\S+\.json)}.freeze

  # Runs `bundle exec <cmd> <args>` from the repo root -- `cmd` is
  # "ruby" for minitest fixtures (a plain `ruby file.rb` is how
  # minitest.rb's own autorun is meant to be invoked) and "rspec" for
  # RSpec fixtures (RSpec.describe only registers an example group;
  # without the rspec executable or `require "rspec/autorun"`,
  # nothing runs it). BULLDOGGER_OUTPUT_DIR points at a fresh temp
  # directory so the fixture's run never touches this repo's own
  # tmp/bulldogger. Returns [stdout, stderr, status, output_dir].
  def run_fixture(cmd, *args, env: {})
    output_dir = Dir.mktmpdir("bulldogger-acceptance-")
    full_env = { "BULLDOGGER_OUTPUT_DIR" => output_dir }.merge(env)
    stdout, stderr, status = Open3.capture3(full_env, "bundle", "exec", cmd, *args, chdir: ROOT)
    [stdout, stderr, status, output_dir]
  end

  def evidence_files(output_dir)
    return [] unless Dir.exist?(output_dir)

    Dir.glob(File.join(output_dir, "run-*", "*.json")).reject { |f| File.basename(f) == "index.json" }
  end

  def evidence_records(output_dir)
    evidence_files(output_dir).map { |f| JSON.parse(File.read(f)) }
  end

  def evidence_for(output_dir, id_fragment)
    evidence_records(output_dir).find { |data| data.dig("test", "id")&.include?(id_fragment) }
  end

  def evidence_paths_from_stdout(text)
    text.scan(EVIDENCE_LINE).flatten
  end

  def no_run_directory?(output_dir)
    !Dir.exist?(output_dir) || Dir.children(output_dir).grep(/\Arun-/).empty?
  end

  # The one run-* directory a red fixture wrote, or nil. Evidence
  # files are written at record time, independent of whether
  # Bulldogger.finish ever runs -- so a passing evidence check alone
  # does not prove the integration's "on suite end, write the index
  # and stop" half actually fired. index.json only exists if finish
  # ran; callers check for it explicitly instead of assuming it.
  def run_dir_for(output_dir)
    Dir.glob(File.join(output_dir, "run-*")).first
  end
end
