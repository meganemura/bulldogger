# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/unit/**/*_test.rb"]
end

task default: :test

# Other tasks (e.g. acceptance, which runs real minitest/RSpec suites
# as child processes) live in tasks/*.rake, owned outside this file.
Dir["tasks/*.rake"].each { |f| load f }
