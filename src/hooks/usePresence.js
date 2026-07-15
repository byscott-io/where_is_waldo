import { useState, useEffect, useCallback, useRef } from 'react';
import { createPresenceReporter } from '../core/presenceReporter';

const DEFAULT_OPTIONS = {
  channelName: 'WhereIsWaldo::PresenceChannel',
  heartbeatInterval: 30000,
  activityTimeout: 30000,
  trackActivity: true,
  trackVisibility: true,
  debug: false,
};

const initialVisible = () =>
  typeof document === 'undefined' ? true : document.visibilityState !== 'hidden';
const initialFocused = () =>
  typeof document === 'undefined' ? true : document.hasFocus();

/**
 * usePresence - browser presence tracking. This is now a thin DOM-sensor
 * wrapper around the framework-agnostic core (../core/presenceReporter): it
 * binds `document`/`window` events to the reporter's `setVisible` /
 * `reportActivity` inputs and mirrors the reporter's state into React state.
 * The heartbeat cadence, activity/visibility state machine, and cable
 * subscription all live in the core, which a React Native reporter reuses.
 *
 * @param {Object} options - see DEFAULT_OPTIONS
 * @returns {{ connected, sessionId, tabVisible, windowFocused, subjectActive, sendHeartbeat }}
 */
export function usePresence(options = {}) {
  const config = { ...DEFAULT_OPTIONS, ...options };

  const [connected, setConnected] = useState(false);
  const [sessionId, setSessionId] = useState(null);
  const [subjectActive, setSubjectActive] = useState(true);
  const [tabVisible, setTabVisible] = useState(initialVisible);
  const [windowFocused, setWindowFocused] = useState(initialFocused);

  const reporterRef = useRef(null);
  // Latest sensor readings, read by the DOM handlers to compute foreground.
  const sensorRef = useRef({ tab: initialVisible(), focus: initialFocused() });

  // Create + start the reporter once (re-created only if the channel changes).
  useEffect(() => {
    const reporter = createPresenceReporter({
      channelName: config.channelName,
      heartbeatInterval: config.heartbeatInterval,
      activityTimeout: config.activityTimeout,
      metadata: config.metadata,
      debug: config.debug,
      onConnected: config.onConnected,
      onDisconnected: config.onDisconnected,
      onChange: (state) => {
        setConnected(state.connected);
        setSubjectActive(state.active);
        if (state.sessionId) setSessionId(state.sessionId);
      },
    });
    reporterRef.current = reporter;
    reporter.start();
    // Seed foreground state from the current sensors.
    reporter.setVisible(sensorRef.current.tab && sensorRef.current.focus);

    return () => {
      reporter.stop();
      reporterRef.current = null;
    };
  }, [config.channelName]); // eslint-disable-line react-hooks/exhaustive-deps

  // Activity sensors -> reporter.reportActivity()
  useEffect(() => {
    if (!config.trackActivity) return undefined;

    const onActivity = () => reporterRef.current?.reportActivity();
    const events = ['mousemove', 'keydown', 'scroll', 'touchstart', 'click'];
    events.forEach((event) => window.addEventListener(event, onActivity, { passive: true }));

    return () => events.forEach((event) => window.removeEventListener(event, onActivity));
  }, [config.trackActivity]);

  // Visibility + focus sensors -> reporter.setVisible(foreground)
  useEffect(() => {
    if (!config.trackVisibility) return undefined;

    const pushForeground = () => {
      reporterRef.current?.setVisible(sensorRef.current.tab && sensorRef.current.focus);
    };
    const onVisibility = () => {
      const visible = document.visibilityState !== 'hidden';
      sensorRef.current.tab = visible;
      setTabVisible(visible);
      pushForeground();
    };
    const onFocus = () => {
      sensorRef.current.focus = true;
      setWindowFocused(true);
      pushForeground();
    };
    const onBlur = () => {
      sensorRef.current.focus = false;
      setWindowFocused(false);
      pushForeground();
    };

    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('focus', onFocus);
    window.addEventListener('blur', onBlur);

    return () => {
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('focus', onFocus);
      window.removeEventListener('blur', onBlur);
    };
  }, [config.trackVisibility]);

  const sendHeartbeat = useCallback((overrides) => {
    reporterRef.current?.sendHeartbeat(overrides);
  }, []);

  return { connected, sessionId, tabVisible, windowFocused, subjectActive, sendHeartbeat };
}

export default usePresence;
