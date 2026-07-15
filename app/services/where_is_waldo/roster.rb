# frozen_string_literal: true

module WhereIsWaldo
  # Live presence roster for an org/account: "who's around, and how present are
  # they right now." Built for efficiency — a single shared ActionCable stream
  # per org, an initial snapshot on subscribe, and compact deltas broadcast only
  # on state transitions (never on steady-state heartbeats).
  #
  # A member's presence is reported per device AND as an overall roll-up:
  #
  #   { id: 7, status: "active", devices: { "web" => "active", "mobile" => "idle" } }
  #
  # `devices[platform]` is that platform's own aggregate status (several browser
  # tabs roll up into one "web" status); `status` is the highest level across
  # all platforms — the "is the user active anywhere?" answer, while
  # `devices["mobile"]` answers "is the user active on mobile?". Each status is:
  #
  #   active      - a live session on that device is tab-visible AND working
  #   idle        - a live session is tab-visible but not actively using
  #   background  - only backgrounded/hidden sessions are live (tab hidden or
  #                 mobile app backgrounded)
  #   offline     - no live sessions (overall status only; absent from devices)
  #
  # Enable by configuring `presence_org` (and optionally `presence_roster`).
  class Roster
    # Activity ranking used to pick a subject's aggregate status from the "most
    # present" of their sessions.
    RANK = { active: 3, idle: 2, background: 1, offline: 0 }.freeze
    DEFAULT_PLATFORM = "web"

    class << self
      # Shared stream name for an org record (nil when org is absent).
      def stream_name(org)
        return nil unless org

        klass = org.class.respond_to?(:base_class) ? org.class.base_class : org.class
        "where_is_waldo:roster:#{klass.name}:#{org.id}"
      end

      # Shared stream name for the org a subject belongs to (nil when the roster
      # is unconfigured or the subject has no org).
      def stream_for_subject(subject)
        stream_name(WhereIsWaldo.config.resolve_org(subject))
      end

      # Full roster state for an org: every member subject with their current
      # aggregate presence. Sent once, on subscribe.
      # @return [Array<Hash>] member state hashes
      def snapshot(org, timeout: nil)
        members = WhereIsWaldo.config.resolve_roster(org)
        return [] unless members

        members_for(members, timeout: timeout).values
      end

      # Member states for an arbitrary AR scope of subjects, keyed by id. Used
      # by :pull to snapshot / diff a viewer's visible scope.
      # @return [Hash{Object => Hash}] id => member hash
      def members_for(scope, timeout: nil)
        return {} unless scope

        records = scope.to_a
        states = states_for(records.map(&:id), timeout: timeout)
        records.to_h { |record| [record.id, build_member(record, states[record.id])] }
      end

      # === Cable message builders — identical shapes across every delivery mode
      # so the client reducer never forks ===

      def snapshot_message(members, mode:)
        message = { type: "roster_snapshot", mode: mode.to_s, members: members }
        message[:poll_interval] = WhereIsWaldo.config.roster_poll_interval if %i[pull nudge].include?(mode.to_sym)
        message[:nudge_jitter] = WhereIsWaldo.config.roster_nudge_jitter if mode.to_sym == :nudge
        message
      end

      def delta_message(member)
        { type: "roster_delta", member: member }
      end

      # Content-free "roster changed, re-poll" trigger (:nudge mode). Carries no
      # identity/state, so it leaks nothing beyond "activity happened".
      def nudge_message
        { type: "roster_nudge" }
      end

      # Tells the client to drop a member who left the viewer's visible scope
      # (distinct from going offline, which stays present with status "offline").
      def removed_message(subject_id)
        { type: "roster_delta", member: { id: subject_id, _removed: true } }
      end

      # Aggregate presence state for a single subject across all their sessions.
      # @return [Hash] { status:, devices: { platform => status } }
      def state_for(subject_id, timeout: nil)
        states_for([subject_id], timeout: timeout).fetch(subject_id, offline_state)
      end

      # Presence status for a subject on a specific device/platform, e.g.
      #   WhereIsWaldo::Roster.device_status(user.id, :mobile) # => "idle"
      # Answers "is the user active on mobile?" vs the overall state_for.
      # @return [String] "active" | "idle" | "background" | "offline"
      def device_status(subject_id, platform, timeout: nil)
        state_for(subject_id, timeout: timeout)[:devices][platform.to_s] || "offline"
      end

      # Broadcast a compact delta for one subject to their org roster stream.
      # Intended to be called ONLY on transitions (connect/disconnect/active
      # flip). No-ops safely when the roster is unconfigured or the subject has
      # no org. Recomputes the subject's aggregate so multi-session state (e.g.
      # a second tab still active) is always correct.
      def publish(subject_id, timeout: nil)
        return false if subject_id.blank?

        subject = find_subject(subject_id)
        stream = stream_name(WhereIsWaldo.config.resolve_org(subject))
        return false unless stream

        member = build_member_by_id(subject, subject_id, timeout: timeout)
        ActionCable.server.broadcast(stream, delta_message(member))
        true
      rescue StandardError => e
        Rails.logger&.warn("[WhereIsWaldo::Roster] publish failed for #{subject_id}: #{e.class}: #{e.message}")
        false
      end

      # Per-viewer stream (:fanout mode). Each viewer streams only their own.
      def viewer_stream(viewer_id)
        "where_is_waldo:roster:viewer:#{viewer_id}"
      end

      # Push a subject's delta to every viewer allowed to see them (:fanout
      # mode). Directional audience (config.presence_audience) makes this correct
      # for arbitrary/asymmetric visibility, at O(audience) broadcasts.
      def publish_fanout(subject_id, timeout: nil)
        return false if subject_id.blank?

        subject = find_subject(subject_id)
        audience = subject && WhereIsWaldo.config.resolve_audience(subject)
        return false unless audience

        message = delta_message(build_member_by_id(subject, subject_id, timeout: timeout))
        audience.pluck(:id).each { |viewer_id| ActionCable.server.broadcast(viewer_stream(viewer_id), message) }
        true
      rescue StandardError => e
        Rails.logger&.warn("[WhereIsWaldo::Roster] fanout failed for #{subject_id}: #{e.class}: #{e.message}")
        false
      end

      # Broadcast a content-free nudge to a subject's org roster stream (:nudge
      # mode). Tells watchers to re-poll; carries no protected data.
      def publish_nudge(subject_id)
        return false if subject_id.blank?

        subject = find_subject(subject_id)
        stream = stream_name(WhereIsWaldo.config.resolve_org(subject))
        return false unless stream

        ActionCable.server.broadcast(stream, nudge_message)
        true
      rescue StandardError => e
        Rails.logger&.warn("[WhereIsWaldo::Roster] nudge failed for #{subject_id}: #{e.class}: #{e.message}")
        false
      end

      private

      # Aggregate state for many subjects in one query, keyed by subject id.
      def states_for(subject_ids, timeout: nil)
        ids = Array(subject_ids).compact.uniq
        return {} if ids.empty?

        threshold = (timeout || WhereIsWaldo.config.timeout).seconds.ago
        subject_col = Presence.subject_column

        rows = Presence.where(subject_col => ids)
                       .where("last_heartbeat > ?", threshold)
                       .to_a

        rows.group_by { |row| row[subject_col] }
            .transform_values { |sessions| aggregate(sessions) }
      end

      # Reduce a subject's live sessions to per-device statuses plus an overall
      # roll-up. Sessions are grouped by platform (so several browser tabs form
      # one "web" status); the overall status is the highest across platforms.
      # @return [Hash] { status: "active", devices: { "web" => "active", ... } }
      def aggregate(sessions)
        devices = sessions.group_by { |s| platform(s) }
                          .transform_values { |sess| platform_level(sess) }
        overall = devices.values.max_by { |level| RANK[level] } || :offline
        {
          status: overall.to_s,
          devices: devices.transform_values(&:to_s)
        }
      end

      # Aggregate activity level for the sessions on one platform.
      def platform_level(sessions)
        sessions.map { |s| session_level(s) }.max_by { |level| RANK[level] } || :offline
      end

      # Activity level of one live session. Uniform across web and mobile:
      # a hidden tab / backgrounded app is :background; a visible/foreground
      # session is :active when working, else :idle.
      def session_level(session)
        return :background unless session.tab_visible

        session.subject_active ? :active : :idle
      end

      def platform(session)
        meta = session.metadata
        value = meta && (meta["platform"] || meta[:platform])
        (value.presence || DEFAULT_PLATFORM).to_s
      end

      # Build a member hash from an already-loaded state map entry.
      def build_member(record, state)
        merge_member(record, state || offline_state)
      end

      # Build a member hash by recomputing the subject's aggregate state.
      def build_member_by_id(record, subject_id, timeout: nil)
        merge_member(record, state_for(subject_id, timeout: timeout), id: subject_id)
      end

      def merge_member(record, state, id: nil)
        data = record ? WhereIsWaldo.config.build_subject_data(record) : {}
        data.merge(
          id: id || record&.id,
          status: state[:status],
          devices: state[:devices]
        )
      end

      def offline_state
        { status: "offline", devices: {} }
      end

      def find_subject(subject_id)
        WhereIsWaldo.config.subject_class_constant&.find_by(id: subject_id)
      end
    end
  end
end
