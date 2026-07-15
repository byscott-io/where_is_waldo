import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';

// Fake cable: capture the subscription's connection handlers + heartbeat calls,
// so we can drive the hook deterministically without a real socket.
const perform = vi.fn();
let handlers = null;

vi.mock('../cable', () => ({
  getConsumer: () => ({
    subscriptions: {
      create: (_params, h) => {
        handlers = h;
        return { perform, unsubscribe: vi.fn() };
      },
    },
  }),
  getCableConfig: () => ({ sessionId: 'sess-1' }),
  handleMessage: vi.fn(),
}));

import { usePresence } from './usePresence';

beforeEach(() => {
  perform.mockClear();
  handlers = null;
});

function heartbeats() {
  return perform.mock.calls.filter((c) => c[0] === 'heartbeat').map((c) => c[1]);
}
function lastHeartbeat() {
  const hb = heartbeats();
  return hb[hb.length - 1];
}
function setVisibility(state) {
  Object.defineProperty(document, 'visibilityState', { value: state, configurable: true });
}

/**
 * Characterization ("golden master") tests for usePresence's OBSERVABLE
 * behavior — written against the original hook so a refactor must preserve them.
 * Assertions target the contract (heartbeats fire on the right transitions with
 * the right tab_visible / subject_active, returned state mirrors the sensors),
 * not byte-exact payloads.
 */
describe('usePresence (characterization)', () => {
  it('subscribes and reflects connected + sessionId once the cable connects', () => {
    const { result } = renderHook(() => usePresence());

    expect(result.current.connected).toBe(false);
    act(() => handlers.connected());

    expect(result.current.connected).toBe(true);
    expect(result.current.sessionId).toBe('sess-1');
  });

  it('sends an immediate tab_visible:false heartbeat and updates state on window blur', () => {
    const { result } = renderHook(() => usePresence());
    act(() => handlers.connected());
    act(() => window.dispatchEvent(new Event('focus'))); // ensure focused first
    perform.mockClear();

    act(() => window.dispatchEvent(new Event('blur')));

    expect(result.current.windowFocused).toBe(false);
    expect(lastHeartbeat()).toMatchObject({ tab_visible: false });
  });

  it('sends a heartbeat and updates state on window focus regain', () => {
    const { result } = renderHook(() => usePresence());
    act(() => handlers.connected());
    act(() => window.dispatchEvent(new Event('blur')));
    perform.mockClear();

    act(() => window.dispatchEvent(new Event('focus')));

    expect(result.current.windowFocused).toBe(true);
    expect(heartbeats().length).toBeGreaterThan(0);
  });

  it('sends a tab_visible:false heartbeat when the tab is hidden', () => {
    renderHook(() => usePresence());
    act(() => handlers.connected());
    perform.mockClear();

    act(() => {
      setVisibility('hidden');
      document.dispatchEvent(new Event('visibilitychange'));
    });

    expect(lastHeartbeat()).toMatchObject({ tab_visible: false });
    setVisibility('visible'); // reset
  });

  it('sends a heartbeat via the returned sendHeartbeat()', () => {
    const { result } = renderHook(() => usePresence());
    act(() => handlers.connected());
    perform.mockClear();

    act(() => result.current.sendHeartbeat());

    expect(heartbeats().length).toBe(1);
  });

  it('marks the subject inactive after the activity timeout, then active on new activity', () => {
    vi.useFakeTimers();
    try {
      const { result } = renderHook(() =>
        usePresence({ activityTimeout: 1000, heartbeatInterval: 10_000_000 }));
      act(() => handlers.connected());

      // Idle past the activity timeout -> inactive.
      act(() => vi.advanceTimersByTime(1200));
      expect(result.current.subjectActive).toBe(false);

      // New activity -> active again, with an immediate subject_active:true beat.
      perform.mockClear();
      act(() => window.dispatchEvent(new Event('mousemove')));
      expect(result.current.subjectActive).toBe(true);
      expect(lastHeartbeat()).toMatchObject({ subject_active: true });
    } finally {
      vi.useRealTimers();
    }
  });
});
