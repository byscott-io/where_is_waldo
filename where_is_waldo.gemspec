# frozen_string_literal: true

require_relative "lib/where_is_waldo/version"

Gem::Specification.new do |spec|
  spec.name = "where_is_waldo"
  spec.version = WhereIsWaldo::VERSION
  spec.authors = ["Scott Gibson"]
  spec.email = ["scott@byscott.io"]

  spec.summary = "Real-time presence tracking for Rails + React applications"
  spec.description = "Track who's online, their activity state, and broadcast messages. " \
                     "Fully configurable - works with any user model, session system, and room concept."
  spec.homepage = "https://github.com/byscott-io/where_is_waldo"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  # Publish to public RubyGems.org — lock the host so a stray `gem push` can't
  # go to the wrong registry.
  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.files = Dir[
    "lib/**/*",
    "app/**/*",
    "config/**/*",
    "VERSION",
    "CHANGELOG.md",
    "LICENSE",
    "README.md"
  ]

  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.0"

  spec.add_development_dependency "database_cleaner-active_record", "~> 2.0"
  spec.add_development_dependency "factory_bot_rails", "~> 6.0"
  spec.add_development_dependency "mock_redis", "~> 0.36"
  spec.add_development_dependency "puma", ">= 7.2.1"
  spec.add_development_dependency "redis", "~> 5.0"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "rubocop", "~> 1.60"
  spec.add_development_dependency "rubocop-rails", "~> 2.23"
  spec.add_development_dependency "rubocop-rspec", "~> 2.26"
  spec.add_development_dependency "sprockets-rails", "~> 3.4"
  spec.add_development_dependency "sqlite3", ">= 2.1"

  spec.metadata["rubygems_mfa_required"] = "true"
end
