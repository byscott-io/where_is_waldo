# frozen_string_literal: true

module WhereIsWaldo
  module Adapters
    class BaseAdapter
      # Register a presence
      # @param session_id [String] Unique session identifier
      # @param subject_id [Integer/String] Subject identifier (user, member, etc.)
      # @param metadata [Hash] Additional data
      # @return [Boolean] success
      def connect(session_id:, subject_id:, metadata: {})
        raise NotImplementedError
      end

      # Remove a presence. Session-scoped disconnect requires both keys so
      # a caller-supplied session_id can't disconnect another subject's row.
      # Subject-only disconnect removes every session for that subject.
      # @param session_id [String] Session identifier (requires subject_id when set)
      # @param subject_id [Integer/String] Subject identifier
      # @return [Boolean] success
      def disconnect(session_id: nil, subject_id: nil)
        raise NotImplementedError
      end

      # Update heartbeat
      # @param session_id [String] Session identifier
      # @param subject_id [Integer/String] Subject identifier (required —
      #   pairs with session_id to disambiguate colliding session ids across
      #   subjects)
      # @param tab_visible [Boolean] Is tab in foreground
      # @param subject_active [Boolean] Recent activity
      # @param metadata [Hash] Additional data
      # @return [Boolean] success
      def heartbeat(session_id:, subject_id:, tab_visible: true, subject_active: true, metadata: {})
        raise NotImplementedError
      end

      # Get all online subject IDs
      # @param timeout [Integer] Seconds threshold
      # @return [Array<Integer>] Subject IDs
      def online_subject_ids(timeout: nil)
        raise NotImplementedError
      end

      # Get all sessions for a subject
      # @param subject_id [Integer/String] Subject identifier
      # @return [Array<Hash>] Presence records
      def sessions_for_subject(subject_id)
        raise NotImplementedError
      end

      # Get live sessions for many subjects in one call, grouped by subject id.
      # Subjects with no live sessions are omitted from the returned hash.
      # Adapters should override for efficiency; this default is a correct but
      # unoptimized fan-out over `sessions_for_subject`.
      # @param subject_ids [Array<Integer/String>] Subject identifiers
      # @param timeout [Integer, nil] Seconds threshold; sessions with
      #   `last_heartbeat` older than `Time.current - timeout` are excluded
      # @return [Hash{Integer/String => Array<Hash>}] subject_id => sessions
      def sessions_for_subjects(subject_ids, timeout: nil)
        ids = Array(subject_ids).compact.uniq
        return {} if ids.empty?

        threshold = Time.current - (timeout || default_timeout)
        ids.each_with_object({}) do |sid, memo|
          live = sessions_for_subject(sid).select { |s| s[:last_heartbeat] && s[:last_heartbeat] >= threshold }
          memo[sid] = live if live.any?
        end
      end

      # Get session status
      # @param session_id [String] Session identifier
      # @param subject_id [Integer/String] Subject identifier — required
      #   for the same reason as heartbeat (see above)
      # @return [Hash, nil] Presence record or nil
      def session_status(session_id, subject_id)
        raise NotImplementedError
      end

      # Remove stale records
      # @param timeout [Integer] Seconds threshold
      # @return [Integer] Number removed
      def cleanup(timeout: nil)
        raise NotImplementedError
      end

      protected

      def config
        WhereIsWaldo.config
      end

      def default_timeout
        config.timeout
      end

      def session_column
        config.session_column
      end

      def subject_column
        config.subject_column
      end
    end
  end
end
