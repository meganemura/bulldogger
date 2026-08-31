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
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  # Requires a second factor for account-level gem operations. Releases
  # go out through RubyGems.org Trusted Publishing, which authenticates
  # with a short-lived OIDC token from the release workflow rather than
  # with an account credential, so this flag costs the release path
  # nothing. See docs/maintenance.md.
  spec.metadata["rubygems_mfa_required"] = "true"

  # Dir glob, not `git ls-files`: this gemspec is written before the
  # files it lists are committed, so a git-based list would be empty.
  # docs/ and skills/ ship with the gem on purpose. An agent that meets
  # bulldogger for the first time meets it through a failure message,
  # with no network: the schema reference and the skill must already be
  # on disk next to the code that wrote the file.
  spec.files = Dir["lib/**/*.rb", "exe/**", "docs/**/*.md", "skills/**/*.md", "README.md", "README.ja.md", "CHANGELOG.md", "LICENSE*"]
  spec.bindir = "exe"
  spec.executables = ["bulldogger"]
  spec.require_paths = ["lib"]

  # No runtime dependency: the core must run on stdlib alone, so an
  # app that adopts bulldogger adds nothing to its own dependency
  # graph. `debug` is development-only, below.
  spec.add_development_dependency "rake", "= 13.4.2"
  spec.add_development_dependency "minitest", "= 6.0.6"
  spec.add_development_dependency "rspec", "= 3.13.2"
  spec.add_development_dependency "debug", "= 1.11.1"
  spec.add_development_dependency "hegeltest", "= 0.1.0"
end
