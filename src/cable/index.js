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
 * @param {Function} options.getToken - Function that returns auth token
 */
export function configureCable(options = {}) {
  config = { ...config, ...options };
  // Reset consumer when config changes
  if (consumer) {
    consumer.disconnect();
    consumer = null;
  }
}

/**
 * Get or create the ActionCable consumer
 * @returns {Consumer}
 */
export function getConsumer() {
  if (!consumer) {
    let url = config.url;

    if (config.getToken) {
      const token = config.getToken();
      if (token) {
        const separator = url.includes('?') ? '&' : '?';
        url = `${url}${separator}token=${encodeURIComponent(token)}`;
      }
    }

    consumer = createConsumer(url);
  }

  return consumer;
}

/**
 * Disconnect and reset the consumer
 */
export function disconnectCable() {
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
