# frozen_string_literal: true

module WhereIsWaldo
  class PresenceService
    class << self
      # Register a new presence
      # @param session_id [String] Unique session identifier
      # @param subject_id [Integer/String] Subject identifier (user, member, etc.)
      # @param metadata [Hash] Additional data
      # @return [Boolean] success
      def connect(session_id:, subject_id:, metadata: {})
        adapter.connect(
          session_id: session_id,
          subject_id: subject_id,
          metadata: metadata
        )
      end

      # Remove a presence by session, or all presences for a subject
      # @param session_id [String] Session identifier (optional)
      # @param subject_id [Integer/String] Subject identifier (optional)
      # @return [Boolean] success
      def disconnect(session_id: nil, subject_id: nil)
        adapter.disconnect(
          session_id: session_id,
          subject_id: subject_id
        )
      end

      # Update heartbeat for a session
      # @param session_id [String] Session identifier
      # @param subject_id [Integer/String] Subject identifier (required —
      #   pairs with session_id to disambiguate colliding session ids across
      #   subjects)
      # @param tab_visible [Boolean] Is tab in foreground
      # @param subject_active [Boolean] Recent activity
      # @param last_activity_at [Integer] Unix timestamp (ms) of last user activity
      # @param metadata [Hash] Additional data to merge
      # @return [Boolean] success
      def heartbeat(session_id:, subject_id:, tab_visible: true, subject_active: true, last_activity_at: nil, metadata: {})
        adapter.heartbeat(
          session_id: session_id,
          subject_id: subject_id,
          tab_visible: tab_visible,
          subject_active: subject_active,
          last_activity_at: last_activity_at,
          metadata: metadata
        )
      end

      # Get online subjects from an AR scope
      # @param scope [ActiveRecord::Relation] Scope to filter
      # @param timeout [Integer] Seconds threshold (defaults to config.timeout)
      # @return [ActiveRecord::Relation] Online subjects from the scope
      def online(scope, timeout: nil)
        online_ids = adapter.online_subject_ids(timeout: timeout)
        scope.where(id: online_ids)
      end

      # Get online subject IDs from an AR scope
      # @param scope [ActiveRecord::Relation] Scope to filter
      # @param timeout [Integer] Seconds threshold (defaults to config.timeout)
      # @return [Array<Integer>] Online subject IDs
      def online_ids(scope, timeout: nil)
        online_ids = adapter.online_subject_ids(timeout: timeout)
        scope.where(id: online_ids).pluck(:id)
      end

      # Get all online subject IDs (no scope filtering)
      # @param timeout [Integer] Seconds threshold
      # @return [Array<Integer>]
      def all_online_ids(timeout: nil)
        adapter.online_subject_ids(timeout: timeout)
      end

      # Get all sessions for a subject
      # @param subject_id [Integer/String] Subject identifier
      # @return [Array<Hash>] Presence records
      delegate :sessions_for_subject, to: :adapter

      # Get live sessions for many subjects in one call, grouped by subject id.
      # Preferred over calling `sessions_for_subject` per id when the caller
      # already has an id list (e.g. roster aggregation) — adapters can (and do)
      # implement this as a bulk read.
      # @param subject_ids [Array<Integer/String>] Subject identifiers
      # @param timeout [Integer, nil] Seconds threshold (defaults to config.timeout)
      # @return [Hash{Integer/String => Array<Hash>}] subject_id => sessions
      delegate :sessions_for_subjects, to: :adapter

      # Get status of a specific session
      # @param session_id [String] Session identifier
      # @param subject_id [Integer/String] Subject identifier — required
      #   for the same reason as heartbeat
      # @return [Hash, nil] Presence record or nil
      delegate :session_status, to: :adapter

      # Check if a subject is online
      # @param subject_id [Integer/String] Subject identifier
      # @return [Boolean]
      def subject_online?(subject_id)
        sessions_for_subject(subject_id).any?
      end

      # Cleanup stale records
      # @param timeout [Integer] Seconds threshold (defaults to config.timeout)
      # @return [Integer] Number of records removed
      def cleanup(timeout: nil)
        adapter.cleanup(timeout: timeout)
      end

      private

      def adapter
        @adapter ||= build_adapter
      end

      def build_adapter
        case WhereIsWaldo.config.adapter
        when :database
          Adapters::DatabaseAdapter.new
        when :redis
          Adapters::RedisAdapter.new
        else
          raise ArgumentError, "Unknown adapter: #{WhereIsWaldo.config.adapter}"
        end
      end

      # Reset adapter (useful for testing or config changes)
      def reset_adapter!
        @adapter = nil
      end
    end
  end
end
