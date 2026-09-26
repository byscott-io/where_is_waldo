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

# CI pins this to each supported redis-rb major in turn, so the Redis adapter is
# exercised on both RESP2 and RESP3. Unset, it resolves by the gemspec range.
gem "redis", ENV["WHERE_IS_WALDO_REDIS_VERSION"] if ENV["WHERE_IS_WALDO_REDIS_VERSION"]
