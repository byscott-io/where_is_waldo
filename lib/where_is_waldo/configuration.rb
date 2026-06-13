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

    # Default audience resolver for the Broadcastable concern. A lambda that,
    # given a record, returns the AR scope to broadcast to (e.g. that record's
    # account members). Set once per app to match its container, e.g.:
    #   config.broadcast_audience = ->(rec) { rec.account.users }
    # Models may override per-model via `broadcasts_realtime(scope: ...)`.
    attr_accessor :broadcast_audience

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

      # Broadcastable default audience (set per app)
      @broadcast_audience = nil
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
