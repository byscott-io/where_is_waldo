import { useEffect, useRef } from 'react';
import { subscribeToEvent } from '../cable';

/**
 * useWaldoEvent - subscribe a component to a raw real-time event type.
 *
 * The component subscribes to a message `type` and receives the payload on
 * every matching cable event; it decides for itself whether it cares about a
 * given record (e.g. `if (data.project_id === myId) ...`). The subscription is
 * automatically torn down when the component unmounts ("out of view"), exactly
 * like a useEffect cleanup.
 *
 * The handler is held in a ref so it always sees the latest props/state without
 * re-subscribing on every render — callers do NOT need to memoize it. The
 * subscription is re-created only when `type` (or an explicit `enabled` flag)
 * changes.
 *
 * @param {string} type - Cable message type, e.g. 'issue_update'
 * @param {Function} handler - Called with (data, message) on each event
 * @param {Object} [options]
 * @param {boolean} [options.enabled=true] - When false, no subscription is made
 *
 * @example
 *   useWaldoEvent('issue_update', (data) => {
 *     if (data.id === issueId) setIssue((prev) => ({ ...prev, ...data }));
 *   });
 */
export function useWaldoEvent(type, handler, options = {}) {
  const { enabled = true } = options;
  const handlerRef = useRef(handler);

  // Keep the ref pointing at the latest handler every render.
  useEffect(() => {
    handlerRef.current = handler;
  });

  useEffect(() => {
    if (!enabled || !type) return undefined;
    const unsubscribe = subscribeToEvent(type, (data, message) => {
      if (handlerRef.current) handlerRef.current(data, message);
    });
    return unsubscribe;
  }, [type, enabled]);
}

export default useWaldoEvent;
