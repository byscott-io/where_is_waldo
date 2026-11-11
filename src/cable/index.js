import { createConsumer } from '@rails/actioncable';

let consumer = null;
let config = {
  url: '/cable',
  getToken: null,
};

// Subscribe-by-event-type registry: message type -> Set of listener fns.
// Components subscribe to a raw event type (see subscribeToEvent /
// useWaldoEvent) and decide for themselves whether they care about a given
// payload. handleMessage dispatches every incoming message to the listeners
// registered for its type.
const listeners = new Map();

/**
 * Subscribe to a raw cable event type. Returns an unsubscribe function.
 * Multiple subscribers per type are supported; each receives (data, message).
 * @param {string} type - The message type to listen for
 * @param {Function} callback - Called with (data, message) on each matching event
 * @returns {Function} unsubscribe
 */
export function subscribeToEvent(type, callback) {
  if (!type || typeof callback !== 'function') return () => {};

  let set = listeners.get(type);
  if (!set) {
    set = new Set();
    listeners.set(type, set);
  }
  set.add(callback);

  return function unsubscribe() {
    const current = listeners.get(type);
    if (!current) return;
    current.delete(callback);
    if (current.size === 0) listeners.delete(type);
  };
}

/**
 * Configure the ActionCable connection
 * @param {Object} options
 * @param {string} options.url - WebSocket URL (default: '/cable')
 * @param {Function} options.getToken - Returns the auth token, or a promise
 *   resolving to it. Called once per connection attempt, so returning a
 *   freshly-refreshed token here is what keeps a long-lived tab connected.
 */
export function configureCable(options = {}) {
  config = { ...config, ...options };
  // A new provider invalidates anything cached from the old one.
  cachedToken = null;
  tokenInFlight = null;
  // Reset consumer when config changes
  if (consumer) {
    stopWatchdog();
    consumer.disconnect();
    consumer = null;
  }
}

// Last token we managed to resolve, for the case where getToken is async.
//
// The URL callback below cannot await: ActionCable calls it synchronously
// while opening a socket. So an async getToken is resolved in the background
// and its result cached here for the NEXT connection attempt -- which costs at
// most one rejected attempt, since ActionCable retries with backoff and the
// retry re-reads this.
let cachedToken = null;
let tokenInFlight = null;

// Resolve getToken, tolerating either a plain value or a promise.
function resolveToken() {
  if (!config.getToken) return null;

  // While an async resolve is outstanding, do NOT call the provider again.
  //
  // Raised in review: the earlier guard only stopped a second promise from
  // being TRACKED, not the provider from being invoked, so a reconnect storm
  // fired its side effect -- typically a refresh request -- on every attempt.
  // It also left that second promise without a rejection handler, which CI
  // caught as unhandled errors. One guard fixes both.
  if (tokenInFlight) return cachedToken;

  let value;
  try {
    value = config.getToken();
  } catch {
    // The provider could not answer at all. Keep the last token rather than
    // dropping a working connection over a storage hiccup -- a cookie
    // accessor can raise outright with site data blocked.
    return cachedToken;
  }

  if (value && typeof value.then === 'function') {
    tokenInFlight = value
      .then((token) => {
        // A null RESOLUTION is ambiguous -- it can mean "could not refresh" --
        // so the previous token is kept and a later retry gets another go.
        // That is the opposite of the synchronous case below, deliberately.
        if (token) cachedToken = token;
        return token;
      })
      .catch(() => null)
      .finally(() => {
        tokenInFlight = null;
      });

    return cachedToken;
  }

  // A SYNCHRONOUS answer is authoritative, including "no token".
  //
  // Raised in review: falling back to the cache here meant that once a
  // provider had returned a token, a later deliberate null -- a sign-out,
  // storage cleared -- kept reconnecting with the OLD token instead of going
  // tokenless and letting the server refuse it properly.
  cachedToken = value || null;
  return cachedToken;
}

// Built fresh for every connection attempt -- see getConsumer.
function buildUrl() {
  const url = config.url;
  const token = resolveToken();
  if (!token) return url;

  const separator = url.includes('?') ? '&' : '?';
  return `${url}${separator}token=${encodeURIComponent(token)}`;
}

// --- Reconnection watchdog -------------------------------------------------
//
// ActionCable's own ConnectionMonitor normally handles reconnecting, and while
// it is running this code deliberately does nothing. The problem is that the
// monitor can be switched off PERMANENTLY, and then nothing in ActionCable
// ever turns it back on:
//
//   close({allowReconnect}) { if (!allowReconnect) { this.monitor.stop() } }
//   stop() { this.stopPolling(); removeEventListener("visibilitychange", ...) }
//
// stop() unregisters the very listener that would notice the tab being
// focused again, so the page is left permanently offline. A server can trigger
// that from the outside by sending a disconnect with reconnect: false, which
// Rails does for an unauthorized or remotely-disconnected connection.
//
// Observed in production: a client's socket closed and the tab then ran for
// SEVEN AND A HALF HOURS making ordinary HTTP requests, visible and focused,
// without a single further WebSocket attempt. Presence stayed empty the whole
// time and anything broadcast to online subscribers missed it. Nothing was
// refused -- nothing was attempted.
//
// A presence library cannot delegate its only recovery path to something that
// can be disabled by the other end. So: while we want a connection, notice a
// monitor that has stopped and start it again.
const WATCHDOG_INTERVAL_MS = 10000;

// Whether a connection is WANTED. False after an intentional disconnect, so
// the watchdog never undoes a deliberate teardown.
let connectionWanted = false;
let watchdogTimer = null;
let watchdogVisibilityHandler = null;

function connectionInternals() {
  // Reaching into ActionCable's internals, so every access is guarded: a
  // future version may rename these, and a presence heartbeat must not be
  // what breaks an upgrade.
  try {
    const connection = consumer && consumer.connection;
    if (!connection) return null;
    return { connection, monitor: connection.monitor || null };
  } catch {
    return null;
  }
}

// Returns what it did, which is what the tests assert on.
export function checkConnection() {
  if (!connectionWanted) return 'not-wanted';

  const internals = connectionInternals();
  if (!internals) return 'no-consumer';

  const { connection, monitor } = internals;

  try {
    if (typeof connection.isOpen === 'function' && connection.isOpen()) return 'open';

    // A running monitor is already retrying with its own backoff. Opening a
    // second socket underneath it would be worse than waiting.
    if (monitor && typeof monitor.isRunning === 'function' && monitor.isRunning()) {
      return 'monitor-running';
    }

    // The monitor has stopped while we still want a connection. Starting it
    // re-registers the visibilitychange listener and resumes polling, and its
    // first poll reopens -- so this hands recovery back to ActionCable rather
    // than running a competing reconnect loop here.
    if (monitor && typeof monitor.start === 'function') {
      monitor.start();
      return 'monitor-restarted';
    }

    // No monitor to restart: open directly.
    if (typeof connection.open === 'function') {
      connection.open();
      return 'opened';
    }

    return 'nothing-to-do';
  } catch {
    // Never let a failed recovery attempt propagate into a caller's render or
    // heartbeat.
    return 'error';
  }
}

function startWatchdog() {
  connectionWanted = true;
  if (watchdogTimer) return;

  watchdogTimer = setInterval(checkConnection, WATCHDOG_INTERVAL_MS);
  // Unref where available so a Node process (tests, SSR) is not held open.
  if (watchdogTimer && typeof watchdogTimer.unref === 'function') watchdogTimer.unref();

  // Our OWN visibility listener, because the monitor's is exactly what gets
  // removed when it stops. Focusing the tab is the moment a person notices
  // things are stale, so it should also be the moment we recover.
  if (typeof document !== 'undefined' && typeof document.addEventListener === 'function') {
    watchdogVisibilityHandler = () => {
      if (document.visibilityState === 'visible') checkConnection();
    };
    document.addEventListener('visibilitychange', watchdogVisibilityHandler);
  }
}

function stopWatchdog() {
  connectionWanted = false;
  if (watchdogTimer) {
    clearInterval(watchdogTimer);
    watchdogTimer = null;
  }
  if (watchdogVisibilityHandler && typeof document !== 'undefined') {
    document.removeEventListener('visibilitychange', watchdogVisibilityHandler);
    watchdogVisibilityHandler = null;
  }
}

/**
 * Get or create the ActionCable consumer
 * @returns {Consumer}
 */
export function getConsumer() {
  if (!consumer) {
    // A FUNCTION, not a string, and this matters more than it looks.
    //
    // ActionCable's Consumer declares `get url()`, which re-runs
    // createWebSocketURL on EVERY connection attempt, and that helper calls a
    // function url each time. Passing a string baked the token in at first
    // connect, so ActionCable's own reconnects -- after a sleep, a network
    // blip, or a server restart -- reused that original token forever.
    //
    // With a short-lived access token that is a silent, permanent failure: the
    // first reconnect after the token expires is rejected, every retry sends
    // the same dead token, and the client ends up connected to nothing while
    // appearing merely idle. Presence empties and any broadcast aimed at
    // "online" subscribers reaches nobody. Resolving per attempt means a
    // refreshed token is picked up by the next retry with no intervention.
    consumer = createConsumer(buildUrl);
    startWatchdog();
  }

  return consumer;
}

/**
 * Disconnect and reset the consumer
 */
export function disconnectCable() {
  // Deliberate: stop wanting a connection first, so the watchdog does not
  // immediately reconnect what the caller just took down.
  stopWatchdog();
  if (consumer) {
    consumer.disconnect();
    consumer = null;
  }
}

/**
 * Get current cable configuration
 * @returns {Object}
 */
export function getCableConfig() {
  return { ...config };
}

/**
 * Handle an incoming message by dispatching to every listener subscribed to
 * its type.
 * @param {Object} message - The message object with type and data
 * @returns {boolean} - Whether at least one listener was invoked
 */
export function handleMessage(message) {
  const { type, data } = message;

  const set = listeners.get(type);
  if (!set || set.size === 0) return false;

  // Iterate a snapshot so a listener that unsubscribes during dispatch is safe.
  Array.from(set).forEach((cb) => {
    try {
      cb(data, message);
    } catch (err) {
      // One bad listener must not block the others.
      // eslint-disable-next-line no-console
      console.error(`[where-is-waldo] listener for "${type}" threw:`, err);
    }
  });

  return true;
}
