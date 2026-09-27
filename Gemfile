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
#
# Setting it to a 6.x constraint also drags mock_redis down from 0.53.0 to
# 0.48.1, because mock_redis 0.53.0 depends on redis ~> 5 and cannot coexist
# with redis 6. That is harmless *only* because the job that sets this runs the
# real-server integration spec alone, which never touches MockRedis. The
# committed lockfile deliberately stays on redis 5.x so mock_redis stays at
# 0.53.0 for every other spec.
#
# So: do not add this pin to a job that runs the full suite, and do not commit a
# lockfile resolved with it set. Either would quietly swap the test double the
# mock-based adapter specs rely on.
gem "redis", ENV["WHERE_IS_WALDO_REDIS_VERSION"] if ENV["WHERE_IS_WALDO_REDIS_VERSION"]
