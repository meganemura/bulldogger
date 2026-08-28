# frozen_string_literal: true

require "tmpdir"
require "json"

# Measures lib/**/*.rb line coverage with stdlib Coverage (contract:
# no simplecov, no :nocov:) across every process this gem's own test
# suite touches -- not just the in-process unit+property run, but
# every child process the acceptance suite spawns (`bundle exec ruby
# fixture.rb`, `bundle exec rspec fixture.rb`), since
# lib/bulldogger/minitest.rb, lib/bulldogger/rspec.rb, and
# lib/bulldogger/integrations/*.rb only ever run inside one of those.
#
# `rake test` and `rake acceptance` both already run as separate
# `ruby` child processes of this Rake process (Rake::TestTask shells
# out), so the same trick that reaches the acceptance suite's own
# grandchildren also reaches them: set RUBYOPT to preload
# test/support/coverage_child_boot.rb, which starts Coverage and
# dumps its result to BULLDOGGER_COVERAGE_DIR on exit, in *every*
# ruby process spawned while these two env vars are set. Each child
# writes its own dump (scoped to lib/ already, by the boot script);
# this task merges them by summing per-line hit counts.
desc "Measure lib/**/*.rb line coverage across every suite; fails below 100%"
task :coverage do
  Dir.mktmpdir("bulldogger-coverage-") do |coverage_dir|
    boot_script = File.expand_path("../test/support/coverage_child_boot.rb", __dir__)
    original_rubyopt = ENV.fetch("RUBYOPT", nil)
    original_coverage_dir = ENV.fetch("BULLDOGGER_COVERAGE_DIR", nil)

    ENV["BULLDOGGER_COVERAGE_DIR"] = coverage_dir
    # The boot script's flag goes first, not last, on the theory that
    # RUBYOPT's -r flags run in listed order. That ordering turns out
    # not to be what decides this, though (confirmed empirically --
    # see the task report): with BUNDLE_GEMFILE inherited, RubyGems'
    # own startup activates Bundler and evaluates every gemspec in the
    # Gemfile.lock -- including this one, whose top line
    # require_relative's lib/bulldogger/version.rb -- before *any* -r
    # flag from RUBYOPT is processed, this one included. So that one
    # line loads, and finishes loading, before Coverage.start ever
    # gets to run in any of these child processes, regardless of flag
    # order. Documented as a known gap, not chased further: it costs
    # exactly that file's one substantive line, and is unrelated to
    # this file's own logic.
    ENV["RUBYOPT"] = ["-r#{boot_script}", original_rubyopt].compact.join(" ")

    begin
      Rake::Task["test"].invoke
      Rake::Task["acceptance"].invoke
    ensure
      ENV["RUBYOPT"] = original_rubyopt
      ENV["BULLDOGGER_COVERAGE_DIR"] = original_coverage_dir
    end

    result = BulldoggerCoverage.merge_dumps(coverage_dir)
    BulldoggerCoverage.report_and_gate(result)
  end
end

module BulldoggerCoverage
  LIB_ROOT = File.expand_path("../lib", __dir__)

  module_function

  # Sums per-line hit counts across every child process's dump. A nil
  # entry (a non-code line: blank, comment, `end`-only in some Ruby
  # versions) stays nil unless some dump reports a real count for it;
  # in practice every dump agrees line-for-line, since they all parse
  # the same file.
  def merge_dumps(coverage_dir)
    merged = {}
    Dir.glob(File.join(coverage_dir, "*.json")).each do |dump_path|
      JSON.parse(File.read(dump_path)).each do |path, cov|
        lines = cov["lines"]
        merged[path] ||= Array.new(lines.size)
        lines.each_index do |i|
          next if lines[i].nil?

          merged[path][i] = (merged[path][i] || 0) + lines[i]
        end
      end
    end
    merged
  end

  # Every lib/**/*.rb file must appear in the merged result, not just
  # every line inside the files that *did* get loaded: keying off
  # result.keys alone would silently pass a file nothing ever
  # required.
  def report_and_gate(result)
    lib_files = Dir.glob(File.join(LIB_ROOT, "**", "*.rb")).sort
    failures = []

    lib_files.each do |path|
      cov = result[path]
      if cov.nil?
        failures << "#{relative(path)}: never loaded by any suite"
        next
      end

      source = File.readlines(path)
      cov.each_index do |i|
        next if cov[i].nil? || !cov[i].zero?

        failures << "#{relative(path)}:#{i + 1}: #{source[i]&.chomp}"
      end
    end

    total = result.values.sum { |lines| lines.compact.size }
    covered = total - result.values.sum { |lines| lines.count(0) }
    percent = total.zero? ? 0.0 : (100.0 * covered / total)
    puts format("Coverage: %d/%d lines (%.1f%%)", covered, total, percent)

    return if failures.empty?

    puts
    puts "Uncovered lines (file:line: source):"
    failures.each { |line| puts "  #{line}" }
    abort("bulldogger: coverage gate failed -- #{failures.size} uncovered line(s), see above")
  end

  def relative(path)
    path.sub("#{File.expand_path('..', LIB_ROOT)}/", "")
  end
end
