# frozen_string_literal: true

# The one line a test_helper.rb adds to turn Bulldogger on for
# Minitest. Kept separate from lib/bulldogger/integrations/minitest.rb
# so that file can stay organized by framework alongside rspec.rb,
# while this stays the short, memorable require path.
require_relative "integrations/minitest"
