# frozen_string_literal: true

module Bulldogger
  module Probe
    # Tracks which target labels currently have a live probe session,
    # process-wide. Two concurrent sessions on the same method would
    # each build their own TracePoint and double-count every call;
    # the contract requires that be caught at start, by name, not
    # discovered later as doubled statistics.
    module Registry
      @mutex = Mutex.new
      @active = {}

      class << self
        def reserve!(labels)
          @mutex.synchronize do
            conflict = labels.find { |label| @active[label] }
            if conflict
              raise ArgumentError, "bulldogger: probe target #{conflict.inspect} is already being probed"
            end

            labels.each { |label| @active[label] = true }
          end
        end

        def release(labels)
          @mutex.synchronize { labels.each { |label| @active.delete(label) } }
        end
      end
    end
  end
end
