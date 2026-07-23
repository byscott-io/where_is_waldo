# frozen_string_literal: true

# The engine's app/* classes name these frameworks in a superclass position, so
# they resolve at load time, not on first use:
#
#   ApplicationCable::Channel < ActionCable::Channel::Base
#   ApplicationJob           < ActiveJob::Base
#   ApplicationRecord        < ActiveRecord::Base
#
# Rails::Engine eager loads every app/* directory, so a host that skips any of
# these railties — `rails new --skip-action-cable` is the common one — fails to
# boot with `NameError: uninitialized constant
# WhereIsWaldo::ApplicationCable::ActionCable`. Requiring them here makes the
# engine self-sufficient instead of silently depending on the host's
# application.rb. The gem depends on the full `rails` gem, so all three are
# guaranteed to be installed.
require "active_record/railtie"
require "active_job/railtie"
require "action_cable/engine"

module WhereIsWaldo
  class Engine < ::Rails::Engine
    isolate_namespace WhereIsWaldo

    # Configure Presence model associations after all code is loaded
    config.after_initialize do
      WhereIsWaldo::Presence.configure_associations! if WhereIsWaldo::Presence.respond_to?(:configure_associations!)
    end
  end
end
