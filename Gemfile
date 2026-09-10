# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# json 3.0 dropped JSON.parse's positional options argument, which
# ActiveSupport::JSON.decode still passes, so every ActiveRecord json column
# raises ArgumentError on deserialize. Fixed in Rails (rails/rails#58601,
# backported to 8-1-stable) but unreleased as of 8.1.3.1. Remove this pin
# once a Rails release includes the fix. Development/CI guard only — this is
# deliberately not a gemspec constraint, so consumers resolve json themselves.
gem "json", "< 3"

group :development, :test do
  gem "rake"
end
