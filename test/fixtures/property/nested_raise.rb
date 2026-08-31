# frozen_string_literal: true

# A recursive method whose exit (raise vs. return) is controlled by a
# small, arbitrarily-nestable plan (a Hash tree; see
# test/property/discriminator_property_test.rb for the generator and
# the pure-Ruby oracle that predicts, for every recursive call this
# produces, whether it should be classified as a raise-exit).
#
# Recursion goes through .run itself, not a separate helper: probing
# "NestedRaiseFixture::Runner.run" then observes one
# :call/:return pair per node in the tree, at every nesting depth --
# exactly what stresses contract-verbs.md's raise-exit discriminator
# (a checkpoint stack, keyed per call) rather than only its outermost
# frame.
module NestedRaiseFixture
  class Boom < StandardError; end

  class Runner
    def self.run(node)
      case node["type"]
      when "raise"
        raise Boom, "boom"
      when "reraise"
        # rescue then bare `raise`: contract-verbs.md measured that a
        # bare re-raise fires :raise again for the same exception, so
        # this node's own delta is +1 (raise) -1 (rescue) +1 (re-raise)
        # = +1 -- still a raise-exit, by a different route than "raise".
        begin
          raise Boom, "boom"
        rescue Boom
          raise
        end
      when "return"
        :ok
      when "rescued"
        begin
          run(node["inner"])
        rescue Boom
          :recovered
        end
      when "unrescued"
        run(node["inner"])
      end
    end
  end
end
