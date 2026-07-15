// Framework-agnostic presence reporter: the session-state -> heartbeat state
// machine, with NO DOM and NO React Native APIs. It owns the ActionCable
// subscription, the activity/visibility state, and the heartbeat cadence
// (interval + immediate beats on transitions). Platform layers feed it sensor
// inputs and it reports state back — so the web hook (DOM listeners) and a
// React Native reporter (AppState + touch) drive the exact same logic.
//
//   const reporter = createPresenceReporter({ metadata: { platform: 'mobile' } });
//   reporter.start();
//   // sensors:
//   reporter.setVisible(isForeground);   // tab hidden / app backgrounded => false
//   reporter.reportActivity();           // a user interaction happened
//   // teardown:
//   reporter.stop();
//
// The cable deps (consumer, cable config, message bus) are injectable so the
// core is unit-testable without a real socket; they default to the shared cable
// module, which works on React Native with the built-in WebSocket.

import { getConsumer, getCableConfig, handleMessage } from '../cable';

const DEFAULTS = {
  channelName: 'WhereIsWaldo::PresenceChannel',
  heartbeatInterval: 30000, // ms
  activityTimeout: 30000, // ms of no activity -> subject_active=false
  metadata: {},
  debug: false,
};

export function createPresenceReporter(options = {}) {
  const config = { ...DEFAULTS, ...options };
  const now = config.now || (() => Date.now());
  const resolveConsumer = config.getConsumer || getConsumer;
  const resolveCableConfig = config.getCableConfig || getCableConfig;
  const dispatch = config.handleMessage || handleMessage;
  const log = (...args) => {
    // eslint-disable-next-line no-console
    if (config.debug) console.log('[PresenceReporter]', ...args);
  };

  let subscription = null;
  let heartbeatTimer = null;
  let activityTimer = null;
  let lastActivityAt = 0;

  // visible = tab/app is foreground & visible; active = recent user activity.
  const state = { connected: false, visible: true, active: true, sessionId: null };

  const emitChange = () => {
    if (config.onChange) config.onChange({ ...state });
  };

  const buildPayload = (overrides = {}) => {
    const payload = {
      tab_visible: overrides.tab_visible ?? state.visible,
      subject_active: overrides.subject_active ?? state.active,
      metadata: config.metadata || {},
    };
    if (lastActivityAt) payload.last_activity_at = lastActivityAt;
    return payload;
  };

  const sendHeartbeat = (overrides = {}) => {
    if (!subscription) return;
    log('heartbeat', overrides);
    subscription.perform('heartbeat', buildPayload(overrides));
  };

  // (Re)arm the inactivity timer: after activityTimeout with no activity, flip
  // to inactive and send an immediate heartbeat announcing it.
  const scheduleInactivity = () => {
    if (activityTimer) clearTimeout(activityTimer);
    activityTimer = setTimeout(() => {
      if (!state.active) return;
      state.active = false;
      emitChange();
      sendHeartbeat({ subject_active: false });
    }, config.activityTimeout);
  };

  const reportActivity = () => {
    lastActivityAt = now();
    if (!state.active) {
      state.active = true;
      emitChange();
      sendHeartbeat({ subject_active: true }); // immediate: inactive -> active
    }
    scheduleInactivity();
  };

  const setVisible = (visible) => {
    if (visible === state.visible) return;
    state.visible = visible;
    emitChange();
    sendHeartbeat(); // immediate: visibility change
    if (visible) reportActivity();
  };

  const startHeartbeatLoop = () => {
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    heartbeatTimer = setInterval(() => sendHeartbeat(), config.heartbeatInterval);
  };

  const start = () => {
    if (subscription) return subscription;

    subscription = resolveConsumer().subscriptions.create(
      { channel: config.channelName, metadata: config.metadata || {} },
      {
        connected() {
          state.connected = true;
          const cable = resolveCableConfig();
          if (cable && cable.sessionId) state.sessionId = cable.sessionId;
          emitChange();
          if (config.onConnected) config.onConnected();
          startHeartbeatLoop();
        },
        disconnected() {
          state.connected = false;
          emitChange();
          if (config.onDisconnected) config.onDisconnected();
        },
        received(message) {
          // Honor targeted (per-session) messages, then route to the event bus.
          if (message && message._target_session && message._target_session !== state.sessionId) {
            return;
          }
          dispatch(message);
        },
      }
    );

    scheduleInactivity();
    return subscription;
  };

  const stop = () => {
    if (heartbeatTimer) {
      clearInterval(heartbeatTimer);
      heartbeatTimer = null;
    }
    if (activityTimer) {
      clearTimeout(activityTimer);
      activityTimer = null;
    }
    if (subscription) {
      subscription.unsubscribe();
      subscription = null;
    }
    state.connected = false;
  };

  return {
    start,
    stop,
    setVisible,
    reportActivity,
    sendHeartbeat,
    getState: () => ({ ...state }),
  };
}

export default createPresenceReporter;
