import { describe, it, expect, beforeEach, vi } from 'vitest';

// Captures what createConsumer is handed, so the URL can be resolved the way
// ActionCable resolves it -- by calling it per connection attempt.
let consumerArgs = [];

vi.mock('@rails/actioncable', () => ({
  createConsumer: (url) => {
    consumerArgs.push(url);
    return { disconnect: () => {}, subscriptions: { create: () => ({}) } };
  },
}));

import { configureCable, getConsumer, disconnectCable } from './index';

// ActionCable's own resolution: `get url()` calls createWebSocketURL, which
// invokes a function url. Modelling that is the whole point -- asserting on
// the string passed to createConsumer would pass even with the old code.
function resolveUrl() {
  const arg = consumerArgs[consumerArgs.length - 1];
  return typeof arg === 'function' ? arg() : arg;
}

beforeEach(() => {
  consumerArgs = [];
  disconnectCable();
  configureCable({ url: '/cable', getToken: null });
});

describe('cable URL and token', () => {
  it('hands createConsumer a FUNCTION, not a baked string', () => {
    configureCable({ url: '/cable', getToken: () => 'tok-1' });
    getConsumer();

    expect(typeof consumerArgs[0]).toBe('function');
  });

  it('re-reads the token on every connection attempt', () => {
    // This is the regression that mattered: ActionCable reconnects by
    // re-resolving the url, so a rotated token must be picked up without
    // recreating the consumer.
    let current = 'first-token';
    configureCable({ url: '/cable', getToken: () => current });
    getConsumer();

    expect(resolveUrl()).toBe('/cable?token=first-token');

    current = 'second-token';
    expect(resolveUrl()).toBe('/cable?token=second-token');
  });

  it('omits the token parameter when there is no token', () => {
    configureCable({ url: '/cable', getToken: () => null });
    getConsumer();

    expect(resolveUrl()).toBe('/cable');
  });

  it('works with no getToken at all', () => {
    configureCable({ url: '/cable', getToken: null });
    getConsumer();

    expect(resolveUrl()).toBe('/cable');
  });

  it('url-encodes the token', () => {
    configureCable({ url: '/cable', getToken: () => 'a b/c+d' });
    getConsumer();

    expect(resolveUrl()).toBe('/cable?token=a%20b%2Fc%2Bd');
  });

  it('uses & when the url already has a query string', () => {
    configureCable({ url: '/cable?foo=1', getToken: () => 'tok' });
    getConsumer();

    expect(resolveUrl()).toBe('/cable?foo=1&token=tok');
  });

  it('survives a getToken that throws, rather than taking the socket down', () => {
    // A storage accessor can throw outright with cookies blocked.
    configureCable({ url: '/cable', getToken: () => { throw new Error('no cookies'); } });
    getConsumer();

    expect(resolveUrl()).toBe('/cable');
  });

  describe('an async getToken', () => {
    it('serves the resolved token on the NEXT attempt', async () => {
      configureCable({ url: '/cable', getToken: () => Promise.resolve('async-token') });
      getConsumer();

      // First attempt has nothing cached yet: no token rather than a hang.
      expect(resolveUrl()).toBe('/cable');

      await vi.waitFor(() => {
        expect(resolveUrl()).toBe('/cable?token=async-token');
      });
    });

    it('does not INVOKE the provider again while a resolve is in flight', async () => {
      // The provider's side effect is usually a refresh request, so a
      // reconnect storm must not fire it per attempt. An earlier version of
      // this guard only avoided tracking a second promise and still called the
      // provider every time -- and dropped the untracked promise without a
      // rejection handler, which CI caught as unhandled errors.
      const getToken = vi.fn(() => Promise.resolve('tok'));
      configureCable({ url: '/cable', getToken });
      getConsumer();

      resolveUrl();
      resolveUrl();
      resolveUrl();

      expect(getToken).toHaveBeenCalledTimes(1);
      await vi.waitFor(() => expect(resolveUrl()).toBe('/cable?token=tok'));
    });

    it('keeps the last good token when a later resolve rejects', async () => {
      let mode = 'ok';
      configureCable({
        url: '/cable',
        getToken: () => (mode === 'ok'
          ? Promise.resolve('good')
          : Promise.reject(new Error('refresh unavailable'))),
      });
      getConsumer();
      resolveUrl();
      await vi.waitFor(() => expect(resolveUrl()).toBe('/cable?token=good'));

      mode = 'fail';
      // The rejection is handled internally -- an unhandled rejection here
      // fails the suite, which is how CI caught the earlier version.
      resolveUrl();
      await vi.waitFor(() => expect(resolveUrl()).toBe('/cable?token=good'));
    });

    it('drops a cached token when the provider is reconfigured', async () => {
      configureCable({ url: '/cable', getToken: () => Promise.resolve('old-app-token') });
      getConsumer();
      resolveUrl();
      await vi.waitFor(() => expect(resolveUrl()).toBe('/cable?token=old-app-token'));

      configureCable({ url: '/cable', getToken: () => Promise.resolve('new-app-token') });
      getConsumer();

      // The old token must NOT leak into the new configuration.
      expect(resolveUrl()).toBe('/cable');
    });
  });

  describe('a provider that stops returning a token', () => {
    it('goes TOKENLESS when a sync provider later returns null', async () => {
      // Sign-out, or storage cleared. Falling back to the cached token here
      // meant reconnecting with the OLD token instead of letting the server
      // refuse a tokenless connection properly. Raised in review.
      let token = 'live-token';
      configureCable({ url: '/cable', getToken: () => token });
      getConsumer();
      expect(resolveUrl()).toBe('/cable?token=live-token');

      token = null;
      expect(resolveUrl()).toBe('/cable');
    });

    it('treats an empty string the same way', async () => {
      let token = 'live-token';
      configureCable({ url: '/cable', getToken: () => token });
      getConsumer();
      resolveUrl();

      token = '';
      expect(resolveUrl()).toBe('/cable');
    });
  });
});
