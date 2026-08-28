# frozen_string_literal: true

module Bulldogger
  # Insertion-ordered, bounded map from an exception object to its
  # captured snapshot. Bounded because most raises are caught and
  # handled by the app and never become a test failure -- without a
  # cap, a suite that raises-and-rescues heavily would grow this map
  # without limit. Matches by object identity (`equal?`), not `hash`/
  # `eql?`, so an exception class that overrides those can't collide
  # with an unrelated exception instance.
  #
  # ObjectSpace::WeakMap was considered and rejected: its eviction is
  # driven by GC timing, which we cannot observe or bound, and its
  # membership semantics would need the same identity-matching logic
  # this class already provides directly.
  class Pending
    Entry = Struct.new(:exception, :snapshot)

    def initialize(max_size)
      @max_size = max_size
      @entries = []
      @evicted = []
      @mutex = Mutex.new
    end

    # First-write-wins: a re-raised exception (rescue; raise) fires
    # :raise again from the rescue frame. That second capture is worth
    # less than the first -- it points at the handler, not the bug --
    # so an exception already in the ring keeps its original snapshot.
    def put(exception, snapshot)
      @mutex.synchronize do
        next if find(exception)

        @entries << Entry.new(exception, snapshot)
        next unless @entries.size > @max_size

        evicted_entry = @entries.shift
        @evicted << evicted_entry.exception
        @evicted.shift if @evicted.size > @max_size
      end
      nil
    end

    def get(exception)
      @mutex.synchronize { find(exception)&.snapshot }
    end

    def evicted?(exception)
      @mutex.synchronize { @evicted.any? { |e| e.equal?(exception) } }
    end

    private

    def find(exception)
      @entries.find { |entry| entry.exception.equal?(exception) }
    end
  end
end
