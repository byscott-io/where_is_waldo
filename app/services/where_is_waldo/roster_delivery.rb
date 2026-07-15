# frozen_string_literal: true

module WhereIsWaldo
  # Pluggable roster delivery strategies. Each app picks a mode per account (via
  # config.roster_mode); the channels dispatch to the matching strategy. The
  # data model (aggregation) and the wire message shapes are shared across all
  # modes — only the *transport/trigger* differs, so the client reducer never
  # forks.
  #
  # Strategies are pure/stateless (any state lives in Rails.cache): they COMPUTE
  # streams + messages and perform cache/broadcast side effects, but the channel
  # owns the actual ActionCable `transmit`/`stream_from`.
  module RosterDelivery
    module_function

    # Resolve a strategy instance for a mode symbol.
    def for(mode)
      case mode.to_sym
      when :broadcast then Broadcast.new
      when :pull then Pull.new
      else
        raise ArgumentError, "Unknown roster_mode: #{mode.inspect}"
      end
    end

    # Base contract. Channels call these; return values drive the channel's I/O.
    class Base
      # @return [Hash] { streams: [names], messages: [cable messages] }
      def subscribe_plan(_subject, _session_id)
        { streams: [], messages: [] }
      end

      # @return [Array<Hash>] cable messages to transmit to the polling client
      def poll_messages(_subject, _session_id)
        []
      end

      # Side effect on a presence transition (usually a broadcast). No return.
      def on_transition(_subject_id); end

      protected

      def config
        WhereIsWaldo.config
      end
    end

    # Instant push to a single shared per-account stream. NO visibility
    # filtering — everyone in the account sees everyone. O(1) per transition.
    class Broadcast < Base
      def subscribe_plan(subject, _session_id)
        org = config.resolve_org(subject)
        stream = Roster.stream_name(org)
        return { streams: [], messages: [] } unless stream

        {
          streams: [stream],
          messages: [Roster.snapshot_message(Roster.snapshot(org), mode: :broadcast)]
        }
      end

      def on_transition(subject_id)
        Roster.publish(subject_id)
      end
    end

    # Heartbeat/poll pull: the client polls; the server transmits a per-viewer,
    # server-filtered snapshot (first poll / resync) or diff (subsequent). The
    # diff baseline lives in Rails.cache keyed per session (tab), TTL'd so a
    # stale/expired cursor self-heals into a full snapshot. Handles ANY
    # visibility rule via config.presence_visible_scope. No broadcasts.
    class Pull < Base
      def subscribe_plan(subject, session_id)
        current = current_members(subject)
        write_baseline(session_id, current)
        { streams: [], messages: [Roster.snapshot_message(current.values, mode: :pull)] }
      end

      def poll_messages(subject, session_id)
        current = current_members(subject)
        baseline = read_baseline(session_id)
        write_baseline(session_id, current)

        # Cache miss / expired cursor -> full snapshot (self-healing resync).
        return [Roster.snapshot_message(current.values, mode: :pull)] if baseline.nil?

        diff_messages(baseline, current)
      end

      # No push work on transition — pull clients poll for changes.
      def on_transition(_subject_id); end

      private

      def current_members(subject)
        Roster.members_for(config.resolve_visible_scope(subject))
      end

      def diff_messages(baseline, current)
        messages = []
        current.each do |id, member|
          prev = baseline[id]
          messages << Roster.delta_message(member) if prev.nil? || presence_changed?(prev, member)
        end
        # Members that left the viewer's visible scope entirely (a visibility
        # change) — tell the client to drop them.
        (baseline.keys - current.keys).each do |gone_id|
          messages << Roster.removed_message(gone_id)
        end
        messages
      end

      def presence_changed?(prev, member)
        prev[:status] != member[:status] || prev[:devices] != member[:devices]
      end

      def read_baseline(session_id)
        Rails.cache.read(baseline_key(session_id))
      end

      def write_baseline(session_id, members)
        Rails.cache.write(baseline_key(session_id), members, expires_in: config.roster_cache_ttl)
      end

      def baseline_key(session_id)
        "where_is_waldo:roster:baseline:#{session_id}"
      end
    end
  end
end
