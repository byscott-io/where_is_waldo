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

        # rubocop:disable Rails/SkipsModelValidations -- intentional for performance
        Presence.upsert(attrs, unique_by: session_column)
        # rubocop:enable Rails/SkipsModelValidations
        true
      rescue StandardError => e
        Rails.logger.error "[WhereIsWaldo] Connect failed: #{e.message}"
        false
      end

      def disconnect(session_id: nil, subject_id: nil)
        scope = build_lookup_scope(session_id: session_id, subject_id: subject_id)
        scope.delete_all
        true
      rescue StandardError => e
        Rails.logger.error "[WhereIsWaldo] Disconnect failed: #{e.message}"
        false
      end

      def heartbeat(session_id:, tab_visible: true, subject_active: true, last_activity_at: nil, metadata: {})
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

        scope = Presence.where(session_column => session_id)

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

      def session_status(session_id)
        scope = Presence.where(session_column => session_id)
        scope = scope.includes(:subject) if config.subject_class_constant
        scope.first&.as_presence_hash
      end

      def cleanup(timeout: nil)
        threshold = (timeout || default_timeout).seconds.ago
        Presence.where(last_heartbeat: ...threshold).delete_all
      end

      private

      def build_lookup_scope(session_id: nil, subject_id: nil)
        if session_id
          Presence.where(session_column => session_id)
        elsif subject_id
          Presence.where(subject_column => subject_id)
        else
          Presence.none
        end
      end
    end
  end
end
