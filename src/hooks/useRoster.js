import { useState, useEffect, useRef, useCallback } from 'react';
import { getConsumer } from '../cable';
import {
  applyRosterMessage,
  sortedMembers,
  onlineMembers,
  isPullMode,
  ROSTER_SNAPSHOT,
  ROSTER_NUDGE,
} from '../core/rosterStore';

const DEFAULT_CHANNEL = 'WhereIsWaldo::RosterChannel';
const DEFAULT_POLL_INTERVAL = 15; // seconds; overridden by the server's snapshot
const DEFAULT_NUDGE_JITTER = 0.5; // seconds; overridden by the server's snapshot

/**
 * usePresenceRoster - live "who's around" roster as data (bring your own UI).
 *
 * The server picks the delivery mode per account and declares it in the initial
 * snapshot. This hook adapts transparently — no client mode config:
 *   - broadcast/fanout : passively receive pushed deltas.
 *   - pull/nudge       : poll the server (`perform('poll')`) on the interval the
 *                        server specifies; the server replies with a filtered
 *                        snapshot (resync) or diff.
 * Either way the shared reducer (../core/rosterStore) keeps `members` as the
 * full, live set (snapshot seeded, deltas patched, removals dropped).
 *
 * Each member: { id, status, devices: { web, mobile, ... }, ...subjectData }.
 *
 * @param {Object} [options]
 * @param {string} [options.channelName] - override the roster channel name
 * @param {boolean} [options.enabled=true] - when false, no subscription is made
 * @returns {{ members: Array, online: Array, onlineCount: number,
 *             byId: Object, connected: boolean, mode: string|null }}
 */
export function usePresenceRoster(options = {}) {
  const { channelName = DEFAULT_CHANNEL, enabled = true } = options;

  const [members, setMembers] = useState([]);
  const [connected, setConnected] = useState(false);
  const [mode, setMode] = useState(null);

  const mapRef = useRef(new Map());
  const pollTimerRef = useRef(null);
  const nudgeTimerRef = useRef(null);
  const nudgeJitterRef = useRef(DEFAULT_NUDGE_JITTER);

  const flush = useCallback(() => {
    setMembers(sortedMembers(mapRef.current));
  }, []);

  useEffect(() => {
    if (!enabled) return undefined;

    const consumer = getConsumer();

    const startPolling = (subscription, intervalSeconds) => {
      if (pollTimerRef.current) return; // already polling
      const ms = (intervalSeconds || DEFAULT_POLL_INTERVAL) * 1000;
      // Small random offset so clients don't poll in lockstep (herd control).
      const jitter = () => 0.85 + Math.random() * 0.3;
      const tick = () => {
        subscription.perform('poll');
        pollTimerRef.current = setTimeout(tick, ms * jitter());
      };
      pollTimerRef.current = setTimeout(tick, ms * jitter());
    };

    // :nudge — on a content-free trigger, re-poll off-cycle after a random
    // jitter (herd control), debounced to one pending re-poll at a time.
    const scheduleNudgePoll = (subscription) => {
      if (nudgeTimerRef.current) return;
      const delay = Math.random() * nudgeJitterRef.current * 1000;
      nudgeTimerRef.current = setTimeout(() => {
        nudgeTimerRef.current = null;
        subscription.perform('poll');
      }, delay);
    };

    const subscription = consumer.subscriptions.create(
      { channel: channelName },
      {
        connected() {
          setConnected(true);
        },
        disconnected() {
          setConnected(false);
        },
        received(message) {
          if (message && message.type === ROSTER_SNAPSHOT) {
            setMode(message.mode || null);
            if (message.nudge_jitter != null) nudgeJitterRef.current = message.nudge_jitter;
            if (isPullMode(message.mode)) startPolling(subscription, message.poll_interval);
          }
          if (message && message.type === ROSTER_NUDGE) {
            scheduleNudgePoll(subscription);
            return; // content-free trigger; nothing to reduce
          }
          const next = applyRosterMessage(mapRef.current, message);
          if (next !== mapRef.current) {
            mapRef.current = next;
            flush();
          }
        },
      }
    );

    return () => {
      if (pollTimerRef.current) {
        clearTimeout(pollTimerRef.current);
        pollTimerRef.current = null;
      }
      if (nudgeTimerRef.current) {
        clearTimeout(nudgeTimerRef.current);
        nudgeTimerRef.current = null;
      }
      subscription.unsubscribe();
    };
  }, [channelName, enabled, flush]);

  const online = onlineMembers(members);
  const byId = {};
  members.forEach((m) => {
    byId[m.id] = m;
  });

  return { members, online, onlineCount: online.length, byId, connected, mode };
}

export default usePresenceRoster;
