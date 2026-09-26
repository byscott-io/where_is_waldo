# frozen_string_literal: true

source "https://rubygems.org"

# Pinned below json 3 for the dev toolchain, not for Rails. Rails 8.1.4 fixed
# its own JSON.parse call, but rubocop depends on json, and letting json float
# to 3.x pulls rubocop up to 1.91 - which rubocop-rspec 2.31 (via this
# gemspec's "~> 2.26") cannot load, so RuboCop aborts before linting anything.
# Lift this together with rubocop-rspec 3.x.
gem "json", "< 3"

gemspec

group :development, :test do
  gem "rake"
end
