# frozen_string_literal: true

module WhereIsWaldo
  class Roster
    # Which roster a session belongs to, and how that is stored.
    #
    # Extracted from Roster so the resolution rules sit together and can be
    # read without the delivery machinery around them.
    module OrgKeys
      # WHICH ROSTER A SESSION BELONGS TO IS DECIDED ONCE, AT CONNECT, AND
      # STORED ON THE PRESENCE ROW.
      #
      # It cannot be re-derived later. The connection knows the container the
      # person is actually working in; a background broadcast an hour later has
      # only a subject id, and a subject can belong to several orgs. Deriving
      # it twice is how the subscriber ends up listening to one stream while
      # the broadcaster writes to another -- which looks exactly like presence
      # being broken, not like a resolution bug.
      #
      # Stored in metadata rather than a column so this needs no migration in
      # any consuming app.
      def org_key(org)
        return nil unless org

        klass = org.class.respond_to?(:base_class) ? org.class.base_class : org.class
        "#{klass.name}:#{org.id}"
      end

      def org_from_key(key)
        type, id = key.to_s.split(":", 2)
        return nil if type.blank? || id.blank?

        type.safe_constantize&.find_by(id: id)
      rescue StandardError
        nil
      end

      # Every org this subject is currently connected in -- usually one, but a
      # person with two tabs in two accounts is present in both and must appear
      # in both rosters. Falls back to resolving from the subject alone for
      # rows written before this existed, and for apps with no container.
      def org_keys_for_subject(subject_id, timeout: nil)
        by_subject = WhereIsWaldo::PresenceService.sessions_for_subjects([subject_id], timeout: timeout)
        org_keys_from(sessions_for(by_subject, subject_id), subject_id)
      end

      # The same answer from sessions the caller has ALREADY loaded. A presence
      # transition needs both the org keys and the subject's aggregate state,
      # and both are derived from one set of session rows -- reading them twice
      # doubles the adapter traffic on the hottest path in the library.
      def org_keys_from(sessions, subject_id)
        keys = sessions.filter_map do |session|
          session.dig(:metadata, ORG_KEY) || session.dig("metadata", ORG_KEY)
        end.uniq
        return keys if keys.any?

        [org_key(WhereIsWaldo.config.resolve_roster_org(find_subject(subject_id)))].compact
      end

      private

      # THE KEY TYPES ON THE TWO SIDES ARE NOT GUARANTEED TO MATCH.
      #
      # The database adapter keys its result by the AR-typecast column value,
      # typically an Integer, while a subject id arriving from a cable
      # connection is often a String -- authenticate_proc returns whatever the
      # host app decides, and connection params are strings. A plain fetch then
      # misses, and the caller falls back to resolving from the subject alone:
      # silently, and straight back to the guess this exists to replace.
      # Comparing as strings is what stops a type difference becoming a wrong
      # roster.
      def sessions_for(by_subject, subject_id)
        return by_subject[subject_id] if by_subject.key?(subject_id)

        wanted = subject_id.to_s
        _, sessions = by_subject.find { |key, _| key.to_s == wanted }
        sessions || []
      end
    end
  end
end
