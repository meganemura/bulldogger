# frozen_string_literal: true

require_relative "lib/bulldogger/version"

Gem::Specification.new do |spec|
  spec.name = "bulldogger"
  spec.version = Bulldogger::VERSION
  spec.authors = ["meganemura"]
  spec.email = ["meganemura@users.noreply.github.com"]

  spec.summary = "A failing test arrives carrying its own evidence."
  spec.description = "Ruby execution evidence for coding agents: failure " \
                      "snapshots captured at the moment a test raises, " \
                      "written as files an agent can read and query."
  spec.homepage = "https://github.com/meganemura/bulldogger"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage

  # Dir glob, not `git ls-files`: this gemspec is written before the
  # files it lists are committed, so a git-based list would be empty.
  # docs/ and skills/ ship with the gem on purpose. An agent that meets
  # bulldogger for the first time meets it through a failure message,
  # with no network: the schema reference and the skill must already be
  # on disk next to the code that wrote the file.
  spec.files = Dir["lib/**/*.rb", "docs/**/*.md", "skills/**/*.md", "README.md", "LICENSE*"]
  spec.require_paths = ["lib"]

  # No runtime dependency: the core must run on stdlib alone, so an
  # app that adopts bulldogger adds nothing to its own dependency
  # graph. `debug` is development-only, below.
  spec.add_development_dependency "rake", "= 13.4.2"
  spec.add_development_dependency "minitest", "= 5.27.0"
  spec.add_development_dependency "rspec", "= 3.13.2"
  spec.add_development_dependency "debug", "= 1.11.1"
  spec.add_development_dependency "hegeltest", "= 0.1.0"
end
