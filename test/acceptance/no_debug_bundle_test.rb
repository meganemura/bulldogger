# frozen_string_literal: true

require_relative "acceptance_helper"
require "minitest/autorun"
require "bundler"

# Reproduces AGENTS.md's measured fact directly: under a real
# `bundle exec` whose Gemfile does not list `debug`, requiring
# "debug/frame_info" raises LoadError, and Bulldogger's :auto
# frame_source falls back to :degraded because of that LoadError --
# not because this suite told it to. That is why this fixture gets
# its own Gemfile in a temp directory instead of reusing the repo's
# own bundle, which does list debug (for the repo's own unit tests).
class NoDebugBundleTest < Minitest::Test
  include BulldoggerAcceptanceHelper

  RED_FIXTURE = File.join(BulldoggerAcceptanceHelper::ROOT, "test/fixtures/minitest_red/red_test.rb")

  def test_auto_frame_source_degrades_when_the_bundle_has_no_debug_gem
    Dir.mktmpdir("bulldogger-no-debug-bundle-") do |bundle_dir|
      gemfile = write_gemfile(bundle_dir)
      bundle_install(gemfile)

      output_dir = Dir.mktmpdir("bulldogger-acceptance-")
      env = { "BUNDLE_GEMFILE" => gemfile, "BULLDOGGER_OUTPUT_DIR" => output_dir }
      stdout = status = nil
      # Children spawned from inside `bundle exec rake` inherit
      # BUNDLE_GEMFILE/RUBYOPT for the *root* bundle; without
      # unbundling first, the child would resolve the root lockfile
      # (which does list debug) regardless of the BUNDLE_GEMFILE we
      # pass it below.
      Bundler.with_unbundled_env do
        stdout, _stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", RED_FIXTURE, chdir: BulldoggerAcceptanceHelper::ROOT)
      end

      refute status.success?
      data = evidence_for(output_dir, "test_deep_raise")
      refute_nil data, "no evidence found; stdout was:\n#{stdout}"
      assert_equal "degraded", data["capture_mode"]
    end
  end

  private

  def write_gemfile(dir)
    gemfile = File.join(dir, "Gemfile")
    File.write(gemfile, <<~RUBY)
      source "https://rubygems.org"
      gem "bulldogger", path: #{BulldoggerAcceptanceHelper::ROOT.inspect}
      gem "minitest", "5.27.0"
    RUBY
    gemfile
  end

  def bundle_install(gemfile)
    Bundler.with_unbundled_env do
      _stdout, stderr, status = Open3.capture3({ "BUNDLE_GEMFILE" => gemfile }, "bundle", "install", "--local")
      assert status.success?, "bundle install --local failed for the no-debug fixture bundle:\n#{stderr}"
    end
  end
end
