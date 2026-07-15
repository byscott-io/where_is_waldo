# frozen_string_literal: true

module WhereIsWaldo
  class PresenceChannel < ApplicationCable::Channel
    def subscribed
      stream_from subject_stream

      register_presence

      # Seed the local transition gate, resolve the roster delivery strategy for
      # this subject's account once, and announce arrival.
      @wiw_tab_visible = true
      @wiw_subject_active = true
      @wiw_roster_strategy = resolve_roster_strategy
      publish_roster_change
    end

    def unsubscribed
      WhereIsWaldo.disconnect(session_id: waldo_session_id)

      # Recompute the subject's aggregate (they may still be present in another
      # tab/device) and announce the change to the org roster.
      publish_roster_change
    end

    def heartbeat(data)
      data = data.with_indifferent_access

      tab_visible = data[:tab_visible] != false
      subject_active = data[:subject_active] != false

      WhereIsWaldo.heartbeat(
        session_id: waldo_session_id,
        tab_visible: tab_visible,
        subject_active: subject_active,
        last_activity_at: data[:last_activity_at],
        metadata: data[:metadata] || {}
      )

      # Efficiency: only touch the roster when THIS session's activity/visibility
      # actually flips. Steady-state heartbeats (no change) cost zero broadcasts.
      return unless roster_transition?(tab_visible, subject_active)

      @wiw_tab_visible = tab_visible
      @wiw_subject_active = subject_active
      publish_roster_change
    end

    private

    def register_presence
      WhereIsWaldo.connect(
        session_id: waldo_session_id,
        subject_id: waldo_subject_id,
        metadata: params[:metadata] || {}
      )
    end

    def roster_transition?(tab_visible, subject_active)
      tab_visible != @wiw_tab_visible || subject_active != @wiw_subject_active
    end

    # Resolve the roster delivery strategy for this subject's account, once, at
    # subscribe. nil when the roster isn't configured or the subject has no org.
    def resolve_roster_strategy
      return nil unless WhereIsWaldo.config.roster_enabled?

      subject = WhereIsWaldo.config.subject_class_constant&.find_by(id: waldo_subject_id)
      org = subject && WhereIsWaldo.config.resolve_roster_org(subject)
      return nil unless org

      WhereIsWaldo::RosterDelivery.for(WhereIsWaldo.config.resolve_mode(org))
    end

    # Let the delivery strategy react to a presence transition. For :poll this
    # is a no-op (clients poll); for :broadcast it pushes a delta to the account
    # stream. Gated to actual transitions by the heartbeat handler.
    def publish_roster_change
      @wiw_roster_strategy&.on_transition(waldo_subject_id)
    end

    def subject_stream
      "where_is_waldo:subject:#{waldo_subject_id}"
    end
  end
end
