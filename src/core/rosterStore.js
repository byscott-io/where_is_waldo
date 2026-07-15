// Framework-agnostic roster store: pure JS, no DOM and no React Native APIs, so
// it is safe to import from the web package AND the mobile (React Native)
// package. It owns the "materialize full state from a snapshot + transition
// deltas" logic and the derivations over it (per-device roll-up, sorting,
// labels, colors) — everything except the sensors and the pixels, which are
// necessarily platform-specific.

// Cable message types exchanged on the roster stream.
export const ROSTER_SNAPSHOT = 'roster_snapshot';
export const ROSTER_DELTA = 'roster_delta';
// Content-free "re-poll now" trigger (:nudge mode). Carries no data.
export const ROSTER_NUDGE = 'roster_nudge';

// Activity ranking, most-present first. Shared by sorting and by the "highest
// across devices" roll-up so web and mobile agree.
export const STATUS_RANK = { active: 3, idle: 2, background: 1, offline: 0 };

// Status -> presence dot color. Platform UIs may theme these, but sharing a
// default keeps web and mobile visually consistent out of the box.
export const STATUS_COLORS = {
  active: '#22c55e', // visible + working
  idle: '#f59e0b', // visible but not actively using
  background: '#9ca3af', // only backgrounded/hidden sessions
  offline: '#d1d5db', // no live sessions
};

export function presenceColor(status) {
  return STATUS_COLORS[status] || STATUS_COLORS.offline;
}

/**
 * Apply an incoming cable message to a members Map (keyed by subject id),
 * returning a NEW Map (immutable update) so callers can trigger re-renders by
 * identity. Unknown message types return the same Map unchanged.
 *
 * - snapshot: replaces the whole roster.
 * - delta: upserts one member. Offline members are KEPT (status "offline") so
 *   the roster stays the full team with live dots rather than vanishing rows.
 *
 * @param {Map<any, Object>} map - current members map
 * @param {Object} message - { type, members? , member? }
 * @returns {Map<any, Object>}
 */
export function applyRosterMessage(map, message) {
  if (!message || !message.type) return map;

  if (message.type === ROSTER_SNAPSHOT) {
    const next = new Map();
    (message.members || []).forEach((m) => next.set(m.id, m));
    return next;
  }

  if (message.type === ROSTER_DELTA && message.member) {
    const next = new Map(map);
    if (message.member._removed) {
      // Member left the viewer's visible scope (a visibility change) — drop it.
      // Distinct from going offline, which arrives as status "offline".
      next.delete(message.member.id);
    } else {
      next.set(message.member.id, message.member);
    }
    return next;
  }

  return map;
}

/**
 * Modes that require the client to poll the server for deltas (vs. passively
 * receiving pushed broadcasts). The server declares the mode in the snapshot.
 */
export function isPollMode(mode) {
  return mode === 'poll' || mode === 'nudge';
}

/**
 * Members Map -> array, sorted most-present first then by display label.
 */
export function sortedMembers(map) {
  const list = Array.from(map.values());
  list.sort((a, b) => {
    const rank = (STATUS_RANK[b.status] ?? 0) - (STATUS_RANK[a.status] ?? 0);
    if (rank !== 0) return rank;
    return String(memberLabel(a)).localeCompare(String(memberLabel(b)));
  });
  return list;
}

/**
 * Only members with a live session (status !== "offline").
 */
export function onlineMembers(members) {
  return members.filter((m) => m.status && m.status !== 'offline');
}

/**
 * That member's status on a specific device/platform, e.g.
 *   deviceStatus(member, 'mobile') // => "idle"
 * Answers "is the user active on mobile?" vs the overall member.status.
 */
export function deviceStatus(member, platform) {
  return (member && member.devices && member.devices[platform]) || 'offline';
}

/**
 * Best-effort display label from a member's subject data.
 */
export function memberLabel(member) {
  if (!member) return '';
  return (
    member.name ||
    [member.first_name, member.last_name].filter(Boolean).join(' ') ||
    member.email ||
    member.username ||
    `#${member.id}`
  );
}
