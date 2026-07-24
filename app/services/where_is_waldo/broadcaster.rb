# frozen_string_literal: true

module WhereIsWaldo
  class Broadcaster
    class << self
      # Broadcast a message to subjects in an AR scope
      # @param scope [ActiveRecord::Relation, ActiveRecord::Base] Subjects to broadcast to
      # @param message_type [String, Symbol] Message type for client handler routing
      # @param data [Hash] Message payload
      def broadcast_to(scope, message_type, data = {})
        subject_ids = extract_subject_ids(scope)
        return if subject_ids.empty?

        message = build_message(message_type, data)

        subject_ids.each do |subject_id|
          ActionCable.server.broadcast(subject_stream(subject_id), message)
        end
      end

      # Broadcast to online subjects only (from an AR scope)
      # @param scope [ActiveRecord::Relation] Scope to filter
      # @param message_type [String, Symbol] Message type
      # @param data [Hash] Message payload
      def broadcast_to_online(scope, message_type, data = {})
        online_ids = PresenceService.online_ids(scope)
        return if online_ids.empty?

        message = build_message(message_type, data)

        online_ids.each do |subject_id|
          ActionCable.server.broadcast(subject_stream(subject_id), message)
        end
      end

      # Broadcast to a specific session
      # @param session_id [String] Session identifier
      # @param subject_id [Integer/String] Subject identifier — required
      #   to disambiguate colliding session ids across subjects
      # @param message_type [String, Symbol] Message type
      # @param data [Hash] Message payload
      def broadcast_to_session(session_id, subject_id, message_type, data = {})
        status = PresenceService.session_status(session_id, subject_id)
        return false unless status

        message = build_message(message_type, data, target_session: session_id)
        ActionCable.server.broadcast(subject_stream(subject_id), message)
        true
      end

      private

      def extract_subject_ids(scope)
        case scope
        when ActiveRecord::Relation
          scope.pluck(:id)
        when ActiveRecord::Base
          [scope.id]
        when Array
          scope.map { |s| s.respond_to?(:id) ? s.id : s }
        else
          Array(scope)
        end
      end

      def build_message(message_type, data, target_session: nil)
        msg = {
          type: message_type.to_s,
          data: data,
          timestamp: Time.current.iso8601
        }
        msg[:_target_session] = target_session if target_session
        msg
      end

      def subject_stream(subject_id)
        "where_is_waldo:subject:#{subject_id}"
      end
    end
  end
end
