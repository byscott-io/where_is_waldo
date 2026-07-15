# frozen_string_literal: true

module WhereIsWaldo
  # Roster subscription. The delivery mode is resolved per account at subscribe
  # time (config.roster_mode) and dispatched to the matching RosterDelivery
  # strategy; the client is told the mode via the snapshot and adapts (listen
  # vs. poll). A subject can only ever see their OWN account's roster (org is
  # derived from the authenticated connection), so it's safe by construction.
  #
  # Modes:
  #   :broadcast - stream_from the shared account stream; deltas are pushed.
  #   :poll      - no stream; the client calls #poll and gets a filtered diff.
  class RosterChannel < ApplicationCable::Channel
    def subscribed
      subject = current_subject
      mode = resolve_mode(subject)
      return reject unless mode

      @wiw_subject = subject
      @wiw_strategy = RosterDelivery.for(mode)
      apply_plan(@wiw_strategy.subscribe_plan(subject, waldo_session_id))
    end

    # Client-driven poll (pull/nudge modes). Transmits a filtered snapshot
    # (first call / resync) or diff since the last poll for this session.
    def poll
      return unless @wiw_strategy

      @wiw_strategy.poll_messages(@wiw_subject, waldo_session_id).each { |message| transmit(message) }
    end

    private

    def resolve_mode(subject)
      org = WhereIsWaldo.config.resolve_roster_org(subject)
      return nil unless org

      WhereIsWaldo.config.resolve_mode(org)
    end

    def apply_plan(plan)
      plan[:streams].each { |stream| stream_from(stream) }
      plan[:messages].each { |message| transmit(message) }
    end

    def current_subject
      return nil unless waldo_subject_id

      WhereIsWaldo.config.subject_class_constant&.find_by(id: waldo_subject_id)
    end
  end
end
