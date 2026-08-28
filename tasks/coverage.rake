# frozen_string_literal: true

require "tmpdir"
require "json"
require "ripper"

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
    # not to be what decides this, though (confirmed empirically): with
    # BUNDLE_GEMFILE inherited, RubyGems'
    # own startup activates Bundler and evaluates every gemspec in the
    # Gemfile.lock -- including this one, whose top line
    # require_relative's lib/bulldogger/version.rb -- before *any* -r
    # flag from RUBYOPT is processed, this one included. So that one
    # line loads, and finishes loading, before Coverage.start ever
    # gets to run in any of these child processes, regardless of flag
    # order. test/test_helper.rb works around it for the unit+property
    # process by re-`load`ing that one file once Coverage is running;
    # see the comment there.
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
  REPO_ROOT = File.expand_path("..", LIB_ROOT)

  # Named ledger of lines this gate accepts as uncovered. Every entry
  # exists for one reason only: stdlib Coverage cannot observe a line
  # executing while a TracePoint callback is already on the stack --
  # a general MRI behavior, not a defect in this codebase, proven as a
  # standalone, committed repro by
  # test/unit/tracepoint_coverage_blind_spot_test.rb. If that test
  # ever starts failing, Ruby has fixed the underlying limitation and
  # every entry below can be removed along with it.
  #
  # This list is currently empty. Every line that was hook-blind for
  # this reason turned out to have a separate, named method that a
  # direct unit test can call outside any TracePoint (search
  # test/unit/**/*_test.rb for "called directly"), including the
  # TracePoint block bodies themselves once each was thinned to a
  # one-line delegation to such a method. An entry only belongs here
  # when a line has no separate method to call -- literally inside a
  # TracePoint block's own body, with no way to reach it except by
  # letting the block fire for real.
  #
  # Not a static exemption list: MAX_LEDGER_ENTRIES is fixed at the
  # reviewed entry count below (0, right now), not at some headroom
  # above it -- a cap with slack would let a future change add an
  # exclusion silently, which is the exact quiet-growth this ledger
  # exists to prevent. Adding a genuinely new entry means raising
  # MAX_LEDGER_ENTRIES in the same change, which is the visible,
  # reviewable act the ratchet forces. #validate! also re-checks every
  # entry's own line against the file on disk on every run -- exact
  # source text, and that the line still sits inside a TracePoint
  # block -- so a line that moves, changes, or stops being inside a
  # TracePoint block fails the gate too, until this list is edited by
  # hand to match reality again.
  LEDGER = [
    # { file: "lib/bulldogger/relative/path.rb", line: 42,
    #   source: "        the exact source text of that line",
    #   reason: "why no direct-call unit test can reach this line --
    #            name the TracePoint block it lives in and why the
    #            block itself has no separate method left to call" },
  ].freeze
  MAX_LEDGER_ENTRIES = 0

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
    Ledger.validate!

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

        line_no = i + 1
        next if Ledger.covers?(relative(path), line_no, source[i]&.chomp)

        failures << "#{relative(path)}:#{line_no}: #{source[i]&.chomp}"
      end
    end

    total = result.values.sum { |lines| lines.compact.size }
    covered = total - result.values.sum { |lines| lines.count(0) }
    percent = total.zero? ? 0.0 : (100.0 * covered / total)
    puts format("Coverage: %d/%d lines (%.1f%%)", covered, total, percent)
    Ledger.report

    return if failures.empty?

    puts
    puts "Uncovered lines (file:line: source):"
    failures.each { |line| puts "  #{line}" }
    abort("bulldogger: coverage gate failed -- #{failures.size} uncovered line(s), see above")
  end

  def relative(path)
    path.sub("#{REPO_ROOT}/", "")
  end

  # The ledger itself, and the two checks that keep it a ratchet
  # rather than a place to quietly stash exclusions: a fixed cap on
  # how many lines it may ever list, and a live re-check that every
  # listed line is still what it claims to be.
  module Ledger
    module_function

    # true only when result_line matches the ledger entry's own
    # recorded source text too, not just its file:line -- a line
    # whose content silently changed must not keep matching just
    # because its position on disk happens to be unchanged.
    def covers?(relative_path, line, result_line_source)
      LEDGER.any? do |entry|
        entry[:file] == relative_path && entry[:line] == line && entry[:source] == result_line_source
      end
    end

    def report
      puts "TracePoint block-body ledger: #{LEDGER.size}/#{MAX_LEDGER_ENTRIES} line(s)"
      LEDGER.each { |entry| puts "  #{entry[:file]}:#{entry[:line]}: #{entry[:reason]}" }
    end

    def validate!
      if LEDGER.size > MAX_LEDGER_ENTRIES
        abort("bulldogger: coverage ledger has #{LEDGER.size} entries, over its fixed cap of " \
              "#{MAX_LEDGER_ENTRIES} -- this gate does not grow the ledger to absorb new gaps, see " \
              "tasks/coverage.rake's own comment on LEDGER")
      end

      LEDGER.each { |entry| validate_entry!(entry) }
    end

    def validate_entry!(entry)
      full_path = File.expand_path(entry[:file], REPO_ROOT)
      actual_source = File.readlines(full_path)[entry[:line] - 1]&.chomp

      if actual_source != entry[:source]
        abort("bulldogger: coverage ledger entry #{entry[:file]}:#{entry[:line]} no longer matches the file on " \
              "disk (ledger says #{entry[:source].inspect}, file has #{actual_source.inspect}) -- update or " \
              "remove this entry")
      end

      return if TracePointBlock.line_inside?(full_path, entry[:line])

      abort("bulldogger: coverage ledger entry #{entry[:file]}:#{entry[:line]} is no longer inside a " \
            "TracePoint block -- this ledger only accepts lines for that specific, verified reason -- update " \
            "or remove this entry")
    end
  end

  # Answers "is this line inside a TracePoint.new(...) block's own
  # body" by parsing the file with Ripper (stdlib; no new dependency)
  # rather than by indentation or keyword counting, which a bare/do
  # block mixed with unrelated if/def/class `end`s cannot reliably
  # tell apart. Every leaf token Ripper's sexp records carries its own
  # [line, column] position; the block's line range is just the min
  # and max of every leaf position found inside its body -- the
  # closing `end`/`}` itself is not a separate leaf, but a ledger
  # entry's line is always a real statement, which always has one.
  module TracePointBlock
    module_function

    def line_inside?(path, line)
      sexp = Ripper.sexp(File.read(path))
      return false unless sexp

      block_line_ranges(sexp).any? { |first, last| line.between?(first, last) }
    end

    def block_line_ranges(node, ranges = [])
      return ranges unless node.is_a?(Array)

      if node[0] == :method_add_block && tracepoint_new_call?(node[1])
        lines = []
        collect_leaf_lines(node[2], lines)
        ranges << [lines.min, lines.max] if lines.any?
      end

      node.each { |child| block_line_ranges(child, ranges) if child.is_a?(Array) }
      ranges
    end

    # call_expr is [:method_add_arg, actual_call, args] when the call
    # has parenthesized arguments (TracePoint.new(:raise), the only
    # shape this codebase uses), or the bare call node itself
    # otherwise -- both are handled so a future argument-less
    # TracePoint.new is not silently missed.
    def tracepoint_new_call?(call_expr)
      return false unless call_expr.is_a?(Array)

      actual_call = call_expr[0] == :method_add_arg ? call_expr[1] : call_expr
      return false unless actual_call.is_a?(Array) && actual_call[0] == :call

      _tag, receiver, _period, method_name = actual_call
      receiver.is_a?(Array) && receiver[0] == :var_ref &&
        receiver[1].is_a?(Array) && receiver[1][0] == :@const && receiver[1][1] == "TracePoint" &&
        method_name.is_a?(Array) && method_name[0] == :@ident && method_name[1] == "new"
    end

    # A leaf token is a 2-element [line, column] Integer pair; every
    # other Ripper sexp node is either a longer tagged Array or a
    # non-Array value, so this recursion bottoms out exactly at
    # position tuples, never mistaking one for anything else.
    def collect_leaf_lines(node, lines)
      return lines unless node.is_a?(Array)

      if node.length == 2 && node[0].is_a?(Integer) && node[1].is_a?(Integer)
        lines << node[0]
      else
        node.each { |child| collect_leaf_lines(child, lines) }
      end
      lines
    end
  end
end
