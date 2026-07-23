# frozen_string_literal: true

module WhereIsWaldo
  class Configuration
    # Storage settings
    # :adapter - :database or :redis
    # :table_name - defaults to 'presences'
    # :redis_client - custom Redis instance (optional)
    # :redis_prefix - key prefix for Redis (for multi-app setups)
    attr_accessor :adapter, :table_name, :redis_client, :redis_prefix

    # Column names - fully configurable
    # :session_column - unique identifier per connection/tab (e.g., :session_id, :jti)
    # :subject_column - who is present (e.g., :user_id, :member_id, :student_id)
    attr_accessor :session_column, :subject_column

    # Subject model (e.g., 'User', 'Member', 'Student')
    # Required for scope-based broadcasting and queries
    attr_accessor :subject_class

    # Optional: proc that returns hash of subject info for presence data
    # Called with the subject record to build presence hash
    attr_accessor :subject_data_proc

    # Timing
    # :timeout - seconds until considered offline (default: 90)
    # :heartbeat_interval - expected heartbeat frequency (default: 30)
    attr_accessor :timeout, :heartbeat_interval

    # ActionCable settings
    # :channel_name - defaults to 'WhereIsWaldo::PresenceChannel'
    # :authenticate_proc - proc to authenticate connection, receives request
    attr_accessor :channel_name, :authenticate_proc

    # :suppress_presence_proc - callable that decides, per connection, whether
    #   to SKIP presence registration for that subscriber. Receives the
    #   ActionCable connection (host apps can read session/cookies/env off it,
    #   e.g. via `connection.request`). Returns truthy to suppress.
    #
    # A suppressed subscriber still subscribes normally — they receive
    # broadcasts to `where_is_waldo:subject:<id>` (WhereIsWaldo.broadcast_to*
    # signaling) and any other Waldo capability — they just don't register a
    # Presence row / heartbeat / roster transition. Use for cases where the
    # WebSocket session is legitimate but shouldn't be counted as "the subject
    # is present", e.g. support-user impersonation tabs.
    #
    #   config.suppress_presence_proc = ->(connection) {
    #     connection.request.session[:su_user].present?
    #   }
    attr_accessor :suppress_presence_proc

    # Default audience resolver for the Broadcastable concern. A lambda that,
    # given a record, returns the AR scope to broadcast to (e.g. that record's
    # account members). Set once per app to match its container, e.g.:
    #   config.broadcast_audience = ->(rec) { rec.account.users }
    # Models may override per-model via `broadcasts_realtime(scope: ...)`.
    attr_accessor :broadcast_audience

    # === Live presence roster ("who's around in my org/account") ===
    #
    # roster_org: given a subject, return the org/container record that
    #   defines the roster boundary. Its class + id key the single shared roster
    #   ActionCable stream, so every member of the same org subscribes to ONE
    #   stream and a presence change is a single O(1) broadcast (not per-member
    #   fan-out). Required to enable the roster feature — nil leaves it inert.
    #     config.roster_org = ->(subject) { subject.account }
    #
    # roster_members: given that org, return the AR scope of member subjects
    #   shown in the roster. Optional — defaults to org.public_send(<subjects>)
    #   inferred from subject_class (User => :users). Provide it to scope the
    #   list, e.g. only active members:
    #     config.roster_members = ->(org) { org.users.active }
    #
    # roster_members_association: association used to build the default roster
    #   from the org when roster_members is unset (defaults to the pluralized
    #   subject_class, e.g. :users).
    attr_accessor :roster_org, :roster_members, :roster_members_association

    # roster_visible_to: given a VIEWER, return the AR scope of subjects
    #   that viewer may see (for :poll/:nudge snapshots + diffs). Handles any
    #   visibility rule server-side. Defaults to the viewer's whole org roster
    #   (everyone-sees-everyone) when unset.
    #     config.roster_visible_to = ->(viewer) { viewer.visible_users }
    #
    # roster_viewers_of: given a SUBJECT, return the AR scope of viewers allowed
    #   to see it (ONLY used by :fanout, Phase 3). Must be the exact inverse of
    #   roster_visible_to.
    attr_accessor :roster_visible_to, :roster_viewers_of

    # roster_mode: delivery strategy, per account. A symbol, or a callable
    #   resolving an account -> mode. MUST be a function of the account (uniform
    #   for all its members). Default :poll (safe: server-side filtered).
    #     :poll       - heartbeat/poll, server-filtered, ~interval latency
    #     :broadcast  - instant shared-stream push, NO filtering (open account)
    #     :nudge      - :poll + content-free trigger (Phase 2)
    #     :fanout     - per-viewer push (Phase 3)
    #     config.roster_mode = ->(account) { account.everyone_admin? ? :broadcast : :poll }
    attr_accessor :roster_mode

    # Tuning (pull/nudge). roster_nudge_jitter (seconds) spreads clients' re-poll
    # after a nudge so a change doesn't stampede every viewer at once.
    attr_accessor :roster_poll_interval, :roster_cache_ttl, :roster_nudge_jitter

    def initialize
      # Storage defaults
      @adapter = :database
      @table_name = "presences"
      @redis_client = nil
      @redis_prefix = "where_is_waldo"

      # Column defaults
      @session_column = :session_id
      @subject_column = :subject_id

      # Subject model (required)
      @subject_class = nil
      @subject_data_proc = nil

      # Timing defaults
      @timeout = 90
      @heartbeat_interval = 30

      # ActionCable defaults
      @channel_name = "WhereIsWaldo::PresenceChannel"
      @authenticate_proc = nil
      @suppress_presence_proc = nil

      # Broadcastable default audience (set per app)
      @broadcast_audience = nil

      # Presence roster (set per app to enable)
      @roster_org = nil
      @roster_members = nil
      @roster_members_association = nil
      @roster_visible_to = nil
      @roster_viewers_of = nil
      @roster_mode = :poll
      @roster_poll_interval = 15
      @roster_cache_ttl = 90
      @roster_nudge_jitter = 0.5
    end

    # Helper to get timeout as duration
    def timeout_duration
      timeout.is_a?(ActiveSupport::Duration) ? timeout : timeout.seconds
    end

    # Helper to get subject class constant
    def subject_class_constant
      return nil if subject_class.blank?

      subject_class.is_a?(String) ? subject_class.safe_constantize : subject_class
    end

    # Resolve the org/container record for a subject (nil if unset/absent).
    def resolve_roster_org(subject)
      return nil unless roster_org && subject

      roster_org.call(subject)
    end

    # Association name used to derive the default roster from an org when
    # roster_members is not configured (e.g. subject_class "User" => :users).
    def members_association
      return roster_members_association if roster_members_association
      return nil if subject_class.blank?

      subject_class.to_s.demodulize.underscore.pluralize.to_sym
    end

    # Resolve the AR scope of member subjects for an org (nil if not resolvable).
    def resolve_members(org)
      return nil unless org

      if roster_members
        roster_members.call(org)
      elsif (assoc = members_association) && org.respond_to?(assoc)
        org.public_send(assoc)
      end
    end

    # True when the live-presence roster feature is configured.
    def roster_enabled?
      !roster_org.nil?
    end

    # Resolve the AR scope of subjects a VIEWER may see. Defaults to the
    # viewer's whole org roster (everyone-sees-everyone) when unset.
    def resolve_visible_to(viewer)
      return nil unless viewer

      if roster_visible_to
        roster_visible_to.call(viewer)
      else
        resolve_members(resolve_roster_org(viewer))
      end
    end

    # Resolve the AR scope of viewers allowed to see a SUBJECT (:fanout only).
    def resolve_viewers_of(subject)
      return nil unless roster_viewers_of && subject

      roster_viewers_of.call(subject)
    end

    # Resolve the delivery mode for an account. Callable roster_mode is invoked
    # with the account; a bare symbol is returned as-is. Defaults to :poll.
    def resolve_mode(account)
      mode = roster_mode
      mode = mode.call(account) if mode.respond_to?(:call)
      (mode || :poll).to_sym
    end

    # Build subject data hash from a subject record
    def build_subject_data(subject)
      return {} unless subject

      if subject_data_proc
        subject_data_proc.call(subject)
      elsif subject.respond_to?(:id)
        { id: subject.id }
      else
        {}
      end
    end
  end
end
