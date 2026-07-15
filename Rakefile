# frozen_string_literal: true

require "json"
# Standard gem tasks: `rake build` (package the .gem), `rake install`,
# `rake release` (tag + push to the allowed_push_host = rubygems.org).
require "bundler/gem_tasks"

namespace :version do
  desc "Show current version"
  task :show do
    puts File.read("VERSION").strip
  end

  desc "Bump version (usage: rake version:bump[0.0.2])"
  task :bump, [:new_version] do |_t, args|
    new_version = args[:new_version]
    abort "Usage: rake version:bump[0.0.2]" unless new_version

    # Update VERSION file
    File.write("VERSION", "#{new_version}\n")

    # Update package.json
    pkg = JSON.parse(File.read("package.json"))
    pkg["version"] = new_version
    File.write("package.json", "#{JSON.pretty_generate(pkg)}\n")

    puts "Version bumped to #{new_version}"
    puts "  - VERSION"
    puts "  - package.json"
    puts "  - lib/where_is_waldo/version.rb (reads from VERSION)"
  end

  desc "Sync package.json version from VERSION file"
  task :sync do
    version = File.read("VERSION").strip
    pkg = JSON.parse(File.read("package.json"))
    pkg["version"] = version
    File.write("package.json", "#{JSON.pretty_generate(pkg)}\n")
    puts "Synced package.json to version #{version}"
  end
end
