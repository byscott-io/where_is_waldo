# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "active_job/railtie"
require "sprockets/railtie"

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
