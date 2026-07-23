# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "sprockets/railtie"

# NOTE: action_cable/engine, active_job/railtie and active_record/railtie are
# deliberately NOT required here. where_is_waldo's engine requires them itself,
# and this dummy app is what proves it — it stands in for a host built with
# `rails new --skip-action-cable`. See spec/where_is_waldo/engine_spec.rb.

Bundler.require(*Rails.groups)

require "where_is_waldo"

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.0
    config.eager_load = false
    config.root = File.expand_path("..", __dir__)

    # Asset pipeline config
    config.assets.enabled = true
    config.assets.compile = true
    config.assets.debug = true
  end
end
