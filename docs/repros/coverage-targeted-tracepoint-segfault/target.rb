# frozen_string_literal: true
# `result = value` below is line 10; the bare `result` return is line
# 11 -- collector.rb's TARGET_LINE default already matches it. That
# plain-read shape mirrors the real crash site
# (test/fixtures/exec/minitest_exec_test.rb:9, also a bare-variable
# return line, one line after its assignment).

GC.stress = true if ENV["REPRO_GC_STRESS"] == "1"

def target(value)
  result = value
  result
end

if ENV["REPRO_THREADS"] == "1"
  threads = 4.times.map do
    Thread.new { 50.times { |i| target(i) } }
  end
  threads.each(&:join)
else
  50.times { |i| target(i) }
end

puts "no crash"
