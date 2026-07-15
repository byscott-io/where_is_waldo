// Cable management
export {
  configureCable,
  getConsumer,
  disconnectCable,
  getCableConfig,
  handleMessage,
  subscribeToEvent,
} from './cable';

// Context and Provider
export {
  PresenceProvider,
  usePresenceContext,
  default as PresenceContext,
} from './context/PresenceContext';

// Hooks
export { usePresence } from './hooks/usePresence';
export { useWaldoEvent } from './hooks/useWaldoEvent';
export { usePresenceRoster } from './hooks/useRoster';

// Framework-agnostic presence reporter core (no DOM) — the shared session-state
// -> heartbeat state machine that usePresence wraps and a React Native reporter
// reuses. See docs for mobile wiring.
export { createPresenceReporter } from './core/presenceReporter';

// Roster core helpers (pure JS, no DOM — shared with the mobile package). Build
// your own UI with these; nothing here renders.
export {
  applyRosterMessage,
  sortedMembers,
  onlineMembers,
  deviceStatus,
  memberLabel,
  presenceColor,
  STATUS_COLORS,
  STATUS_RANK,
  ROSTER_SNAPSHOT,
  ROSTER_DELTA,
} from './core/rosterStore';
