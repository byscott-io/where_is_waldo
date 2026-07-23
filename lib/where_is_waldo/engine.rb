# frozen_string_literal: true

module WhereIsWaldo
  class Engine < ::Rails::Engine
    isolate_namespace WhereIsWaldo

    # Configure Presence model associations after all code is loaded
    config.after_initialize do
      WhereIsWaldo::Presence.configure_associations! if WhereIsWaldo::Presence.respond_to?(:configure_associations!)
    end
  end
end
