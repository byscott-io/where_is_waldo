# frozen_string_literal: true

require "where_is_waldo/version"
require "where_is_waldo/configuration"
require "where_is_waldo/engine" if defined?(Rails)

module WhereIsWaldo
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def config
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # === Presence Management ===

    def connect(...)
      PresenceService.connect(...)
    end

    def disconnect(...)
      PresenceService.disconnect(...)
    end

    def heartbeat(...)
      PresenceService.heartbeat(...)
    end

    # === Queries ===

    # Get online subjects from a scope
    # @example WhereIsWaldo.online(org.members) => AR relation of online members
    def online(scope, timeout: nil)
      PresenceService.online(scope, timeout: timeout)
    end

    # Get online subject IDs from a scope
    # @example WhereIsWaldo.online_ids(org.members.admin)
    def online_ids(scope, timeout: nil)
      PresenceService.online_ids(scope, timeout: timeout)
    end

    # Get all online subject IDs (no scope filtering)
    def all_online_ids(timeout: nil)
      PresenceService.all_online_ids(timeout: timeout)
    end

    delegate :subject_online?, to: :PresenceService

    delegate :sessions_for_subject, to: :PresenceService

    delegate :session_status, to: :PresenceService

    def cleanup(timeout: nil)
      PresenceService.cleanup(timeout: timeout)
    end

    # === Presence roster (live presence awareness) ===

    # Full roster state for an org record (every member + current presence).
    def roster_snapshot(org, timeout: nil)
      Roster.snapshot(org, timeout: timeout)
    end

    # Aggregate presence state ({ status:, devices: }) for one subject.
    def roster_state_for(subject_id, timeout: nil)
      Roster.state_for(subject_id, timeout: timeout)
    end

    # Presence status for a subject on a specific device/platform.
    # @example WhereIsWaldo.presence_on(user.id, :mobile) # => "idle"
    def presence_on(subject_id, platform, timeout: nil)
      Roster.device_status(subject_id, platform, timeout: timeout)
    end

    # Broadcast a compact presence delta for a subject to their org's roster
    # stream. Call on transitions only (usually automatic via PresenceChannel).
    def publish_presence(subject_id, timeout: nil)
      Roster.publish(subject_id, timeout: timeout)
    end

    # Shared roster stream name for the org a subject belongs to.
    def roster_stream_for(subject)
      Roster.stream_for_subject(subject)
    end

    # === Broadcasting ===

    # Broadcast to subjects in a scope
    # @example WhereIsWaldo.broadcast_to(org.members, :notification, { message: "Hello" })
    def broadcast_to(scope, message_type, data = {})
      Broadcaster.broadcast_to(scope, message_type, data)
    end

    # Broadcast only to online subjects in a scope
    # @example WhereIsWaldo.broadcast_to_online(org.members, :alert, { message: "Urgent" })
    def broadcast_to_online(scope, message_type, data = {})
      Broadcaster.broadcast_to_online(scope, message_type, data)
    end

    # Broadcast to a specific session
    # @example WhereIsWaldo.broadcast_to_session(session_id, :force_logout, { reason: "..." })
    def broadcast_to_session(session_id, message_type, data = {})
      Broadcaster.broadcast_to_session(session_id, message_type, data)
    end
  end
end
