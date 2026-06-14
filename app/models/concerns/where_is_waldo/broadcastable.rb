# frozen_string_literal: true

module WhereIsWaldo
  # Opt a model into real-time broadcasting. Include the concern and declare
  # which lifecycle events should push over the cable:
  #
  #   class Person < ApplicationRecord
  #     include WhereIsWaldo::Broadcastable
  #     broadcasts_realtime                                   # create + update + destroy
  #   end
  #
  #   broadcasts_realtime on: %i[create update]               # subset
  #   broadcasts_realtime on: :update, if: -> { saved_change_to_status? }
  #   broadcasts_realtime scope: ->(rec) { rec.organization.users }
  #
  # Event names follow "<model>_<verb>" — created / update / destroyed — e.g.
  # person_created, person_update, person_destroyed (matching the convention
  # issuesbyscott already uses). The client subscribes with useWaldoEvent.
  #
  # Audience defaults to `WhereIsWaldo.configuration.broadcast_audience` (set
  # once per app, e.g. ->(rec) { rec.account.users }); override per model with
  # `scope:`. Payload defaults to a minimal `{ id: }` (so clients refetch);
  # override `realtime_payload` on the model to push a richer shape for
  # patch-in-place rendering.
  module Broadcastable
    extend ActiveSupport::Concern

    HOOKS = {
      create: %i[after_create_commit created],
      update: %i[after_update_commit update],
      destroy: %i[after_destroy_commit destroyed]
    }.freeze

    class_methods do
      def broadcasts_realtime(on: %i[create update destroy], scope: nil, **guard)
        guard = guard.slice(:if, :unless)
        Array(on).each do |event|
          hook, verb = HOOKS.fetch(event.to_sym) do
            raise ArgumentError, "broadcasts_realtime: unknown event #{event.inspect}"
          end
          # Block form runs in instance context; `verb`/`scope` are captured.
          public_send(hook, **guard) { wiw_broadcast(verb, scope) }
        end
      end
    end

    # Override on the model to shape the payload (default: minimal { id: }).
    def realtime_payload
      { id: id }
    end

    private

    def wiw_broadcast(verb, scope)
      return unless defined?(::WhereIsWaldo)

      audience = wiw_audience(scope)
      return if audience.blank?

      ::WhereIsWaldo.broadcast_to(audience, wiw_event_name(verb), wiw_payload(verb))
    rescue StandardError => e
      Rails.logger&.warn(
        "[WhereIsWaldo::Broadcastable] #{self.class.name}##{id} #{verb} broadcast failed: #{e.class}: #{e.message}"
      )
    end

    def wiw_audience(scope)
      resolver = scope || ::WhereIsWaldo.configuration.broadcast_audience
      return nil unless resolver

      instance_exec(self, &resolver)
    end

    def wiw_event_name(verb)
      # Use the STI base class so subclasses (e.g. Widget::Grid) broadcast the
      # base event name ("widget_update"), not the subclass ("grid_update").
      klass = self.class.respond_to?(:base_class) ? self.class.base_class : self.class
      "#{klass.model_name.element}_#{verb}"
    end

    def wiw_payload(verb)
      verb == :destroyed ? { id: id } : realtime_payload
    end
  end
end
