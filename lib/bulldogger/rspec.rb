# frozen_string_literal: true

# The one line a spec_helper.rb adds to turn Bulldogger on for RSpec.
# Kept separate from lib/bulldogger/integrations/rspec.rb so that file
# can stay organized by framework alongside minitest.rb, while this
# stays the short, memorable require path.
require_relative "integrations/rspec"
