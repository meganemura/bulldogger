# frozen_string_literal: true

# Loaded only via RUBYOPT="-r<this file>", and only when
# BULLDOGGER_COVERAGE_DIR is set -- `rake coverage` is the only caller
# that sets either. Every acceptance check spawns the code under test
# as a real child process (`bundle exec ruby fixture.rb`, `bundle exec
# rspec fixture.rb`); that child process is the only place
# lib/bulldogger/minitest.rb, lib/bulldogger/rspec.rb, and
# lib/bulldogger/integrations/*.rb ever run, so measuring them at all
# means starting Coverage inside that same child, before it requires
# anything, and handing the result back to the parent for merging.
dir = ENV["BULLDOGGER_COVERAGE_DIR"]
if dir
  require "coverage"
  Coverage.start(lines: true)

  at_exit do
    require "json"
    lib_root = File.expand_path("../../lib", __dir__)
    result = Coverage.result
    # Only this gem's own lib/ files are relevant to the gate; keeping
    # the dump scoped to them (rather than every gem this child
    # process happens to load) keeps each child's JSON small.
    scoped = result.select { |path, _| path.start_with?("#{lib_root}/") }
    out_path = File.join(dir, "#{Process.pid}-#{rand(1_000_000)}.json")
    File.write(out_path, JSON.generate(scoped))
  end
end
