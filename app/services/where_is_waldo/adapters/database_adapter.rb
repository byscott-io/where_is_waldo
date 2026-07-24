# frozen_string_literal: true

module WhereIsWaldo
  module Adapters
    class DatabaseAdapter < BaseAdapter
      def connect(session_id:, subject_id:, metadata: {})
        now = Time.current

        attrs = {
          session_column => session_id,
          subject_column => subject_id,
          connected_at: now,
          last_heartbeat: now,
          tab_visible: true,
          subject_active: true,
          last_activity: now,
          metadata: metadata,
          created_at: now,
          updated_at: now
        }

        # (subject, session) is the unique key — see the install migration
        # template. Keying on session alone would let a caller-supplied
        # session_id colliding across two subjects upsert onto each other's
        # row.
        # rubocop:disable Rails/SkipsModelValidations -- intentional for performance
        Presence.upsert(attrs, unique_by: [subject_column, session_column])
        # rubocop:enable Rails/SkipsModelValidations
        true
      rescue StandardError => e
        Rails.logger.error "[WhereIsWaldo] Connect failed: #{e.message}"
        false
      end

      def disconnect(session_id: nil, subject_id: nil)
        raise ArgumentError, "disconnect(session_id:) requires subject_id:" if session_id && !subject_id

        scope = build_lookup_scope(session_id: session_id, subject_id: subject_id)
        scope.delete_all
        true
      rescue ArgumentError
        raise
      rescue StandardError => e
        Rails.logger.error "[WhereIsWaldo] Disconnect failed: #{e.message}"
        false
      end

      # rubocop:disable Metrics/ParameterLists, Layout/LineLength
      def heartbeat(session_id:, subject_id:, tab_visible: true, subject_active: true, last_activity_at: nil, metadata: {})
        # rubocop:enable Metrics/ParameterLists, Layout/LineLength
        now = Time.current
        updates = {
          last_heartbeat: now,
          tab_visible: tab_visible,
          subject_active: subject_active,
          updated_at: now
        }
        # Update last_activity: use JS timestamp if provided, otherwise use current time when active
        if last_activity_at
          updates[:last_activity] = Time.zone.at(last_activity_at / 1000.0)
        elsif subject_active
          updates[:last_activity] = now
        end
        updates[:metadata] = metadata if metadata.present?

        # Scope by both — a caller-supplied session_id shouldn't be able to
        # heartbeat another subject's row.
        scope = Presence.where(session_column => session_id, subject_column => subject_id)

        # rubocop:disable Rails/SkipsModelValidations -- intentional for performance
        scope.update_all(updates).positive?
        # rubocop:enable Rails/SkipsModelValidations
      rescue StandardError => e
        Rails.logger.error "[WhereIsWaldo] Heartbeat failed: #{e.message}"
        false
      end

      def online_subject_ids(timeout: nil)
        threshold = (timeout || default_timeout).seconds.ago

        Presence.where("last_heartbeat > ?", threshold)
                .distinct
                .pluck(subject_column)
      end

      def sessions_for_subject(subject_id)
        scope = Presence.where(subject_column => subject_id)
        scope = scope.includes(:subject) if config.subject_class_constant
        scope.map(&:as_presence_hash)
      end

      def sessions_for_subjects(subject_ids, timeout: nil)
        ids = Array(subject_ids).compact.uniq
        return {} if ids.empty?

        threshold = (timeout || default_timeout).seconds.ago
        scope = Presence.where(subject_column => ids).where("last_heartbeat > ?", threshold)
        scope = scope.includes(:subject) if config.subject_class_constant
        scope.group_by { |row| row[subject_column] }
             .transform_values { |rows| rows.map(&:as_presence_hash) }
      end

      def session_status(session_id, subject_id)
        scope = Presence.where(session_column => session_id, subject_column => subject_id)
        scope = scope.includes(:subject) if config.subject_class_constant
        scope.first&.as_presence_hash
      end

      def cleanup(timeout: nil)
        threshold = (timeout || default_timeout).seconds.ago
        Presence.where(last_heartbeat: ...threshold).delete_all
      end

      private

      def build_lookup_scope(session_id: nil, subject_id: nil)
        if session_id && subject_id
          Presence.where(session_column => session_id, subject_column => subject_id)
        elsif subject_id
          Presence.where(subject_column => subject_id)
        else
          Presence.none
        end
      end
    end
  end
end
