import { createConsumer } from '@rails/actioncable';

let consumer = null;
let config = {
  url: '/cable',
  getToken: null,
  handlers: {},
};

// Subscribe-by-event-type registry: message type -> Set of listener fns.
// This is the modern API (see subscribeToEvent / useWaldoEvent): any number
// of components can subscribe to a raw event type and decide for themselves
// whether they care about a given payload. It coexists with the legacy
// `config.handlers` map (single handler per type) for backward compatibility —
// handleMessage fans out to BOTH.
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
 * @param {Object} options.handlers - Message type handlers { type: handler }
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
 * Register a message handler for a specific type
 * @param {string} messageType - The message type to handle
 * @param {Function} handler - Handler function receiving (data, message)
 */
export function registerHandler(messageType, handler) {
  config.handlers[messageType] = handler;
}

/**
 * Unregister a message handler
 * @param {string} messageType - The message type to unregister
 */
export function unregisterHandler(messageType) {
  delete config.handlers[messageType];
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
 * Get registered handlers
 * @returns {Object}
 */
export function getHandlers() {
  return config.handlers;
}

/**
 * Handle an incoming message by routing to registered handler
 * @param {Object} message - The message object with type and data
 * @returns {boolean} - Whether a handler was found and called
 */
export function handleMessage(message) {
  const { type, data } = message;
  let handled = false;

  // Legacy single-handler path (configureCable({ handlers })) — kept for
  // backward compatibility with apps that haven't migrated to subscribeToEvent.
  const handler = config.handlers[type];
  if (handler) {
    handler(data, message);
    handled = true;
  }

  // Modern subscribe-by-event-type path: fan out to every registered listener.
  // Iterate a snapshot so a listener that unsubscribes during dispatch is safe.
  const set = listeners.get(type);
  if (set && set.size) {
    Array.from(set).forEach((cb) => {
      try {
        cb(data, message);
      } catch (err) {
        // One bad listener must not block the others.
        // eslint-disable-next-line no-console
        console.error(`[where-is-waldo] listener for "${type}" threw:`, err);
      }
    });
    handled = true;
  }

  return handled;
}
