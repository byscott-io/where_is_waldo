# WhereIsWaldo

Real-time presence tracking for Rails + React using ActionCable.

## Features

- **Presence tracking** - know who's online
- **Scope-based queries** - `online(org.users.admin)`
- **Targeted broadcasting** - send to any AR scope
- **Event subscriptions** - components subscribe by event type (`useWaldoEvent`)
- **Activity monitoring** - tab visibility, user activity
- **Multi-session** - same user, multiple tabs/devices
- **Flexible storage** - database or Redis

## Quickstart

### 1. Install

```ruby
# Gemfile
gem 'where_is_waldo', github: 'byscott-io/where_is_waldo'
```

```bash
# Database adapter (default)
rails generate where_is_waldo:install --subject_column=user_id
rails db:migrate

# Redis adapter (no migration needed)
rails generate where_is_waldo:install --adapter=redis --subject_column=user_id
```

```bash
npm install @byscott-io/where-is-waldo @rails/actioncable
```

### 2. Configure

```ruby
# config/initializers/where_is_waldo.rb
WhereIsWaldo.configure do |config|
  config.subject_class = "User"
  config.authenticate_proc = ->(request) {
    # Return user_id from your auth token
    decode_token(request.params[:token])[:user_id]
  }
end
```

```jsx
// app.jsx — configure the connection once, wrap the app
import { configureCable, PresenceProvider } from '@byscott-io/where-is-waldo';

configureCable({
  url: '/cable',
  getToken: () => localStorage.getItem('token'),
  presence: {
    debug: true,  // Enable console logging for troubleshooting
  },
});

<PresenceProvider>
  <App />
</PresenceProvider>
```

```jsx
// any component — subscribe to an event type and filter the payload yourself.
// Auto-unsubscribes on unmount; no central handler config.
import { useWaldoEvent } from '@byscott-io/where-is-waldo';

function Notifications() {
  useWaldoEvent('notification', (data) => showToast(data.message));
  useWaldoEvent('force_logout', () => logout());
  return null;
}
```

### 3. Use

```ruby
# Query who's online
WhereIsWaldo.online(org.users)           # => AR relation
WhereIsWaldo.online(org.users.admin)     # => filter by scope
WhereIsWaldo.subject_online?(user.id)    # => true/false

# Broadcast messages
WhereIsWaldo.broadcast_to(org.users, :notification, { message: "Hello!" })
WhereIsWaldo.broadcast_to(user, :force_logout, { reason: "Password changed" })
```

---

## Detailed Documentation

### Server Configuration

```ruby
WhereIsWaldo.configure do |config|
  config.adapter = :database            # or :redis
  config.table_name = "presences"
  config.session_column = :session_id
  config.subject_column = :user_id      # or :member_id, :student_id
  config.subject_class = "User"         # or "Member", "Student"

  config.timeout = 90                   # seconds until offline
  config.heartbeat_interval = 30

  # Optional: custom subject data in presence hash. NOTE: with the roster
  # enabled, these fields are broadcast to every member of the org — see
  # Security.
  config.subject_data_proc = ->(user) {
    { id: user.id, name: user.name, avatar: user.avatar_url }
  }

  # Live presence roster (see "Live Presence Roster"). Set presence_org to
  # enable; presence_roster is optional (defaults to org.<subjects>).
  config.presence_org = ->(user) { user.account }
  config.presence_roster = ->(org) { org.users.active }

  # Redis adapter
  # config.redis_client = Redis.new(url: ENV["REDIS_URL"])
end
```

### Querying Presence

```ruby
# Get online subjects from any AR scope
WhereIsWaldo.online(org.users)
WhereIsWaldo.online(User.where(role: "admin"))
WhereIsWaldo.online(classroom.students)

# Get just IDs
WhereIsWaldo.online_ids(org.users)

# Check specific subject
WhereIsWaldo.subject_online?(user.id)

# Get all sessions for a subject
WhereIsWaldo.sessions_for_subject(user.id)
# => [{ session_id: "...", tab_visible: true, subject_active: false, ... }]
```

### Broadcasting

```ruby
# To any AR scope
WhereIsWaldo.broadcast_to(org.users, :notification, { message: "Hi" })
WhereIsWaldo.broadcast_to(org.users.admin, :alert, { level: "warning" })

# Only to online subjects
WhereIsWaldo.broadcast_to_online(org.users, :update, { data: "..." })

# To a single subject (all their sessions)
WhereIsWaldo.broadcast_to(user, :force_logout, {})

# To a specific session
WhereIsWaldo.broadcast_to_session(session_id, :warning, { message: "..." })
```

### Live Presence Roster ("who's around in my org")

A ready-made way to show live presence awareness across an org/account — who's
here right now, on what device, and how active. It is built as **data, not UI**:
the server keeps the client's roster in sync and you render whatever component
you like.

**Delivery is a per-account strategy** so you can trade latency × cost ×
visibility-enforcement to fit your app. The server picks the mode and the client
adapts automatically (no client mode config). Modes (default `:pull`):

| Mode | Latency | Visibility | Cost/transition |
|------|---------|------------|-----------------|
| `:pull` (default) | ~poll interval | server-side query — **any** rule | flat (1 cached query/poll) |
| `:nudge` | near-instant | server-side query — **any** rule | O(1) content-free trigger + filtered poll |
| `:fanout` | instant | server-side per-viewer — **any** rule (incl. asymmetric) | O(audience) |
| `:broadcast` | instant | **none** (everyone in account sees everyone) | O(1) |

`:pull` sends a full **snapshot** on connect, then the client polls and the
server replies with a server-*filtered* diff (baseline cached per session,
TTL'd for auto-resync) — so arbitrary/asymmetric visibility "just works" via
`presence_visible_scope`. `:nudge` is `:pull` plus a content-free "re-poll"
broadcast on each transition, so clients refresh near-instantly instead of
waiting for the next interval — same airtight server-side filtering, just lower
latency; the nudge carries no identity/state (only "activity happened").
`:fanout` pushes instantly to a **per-viewer** stream: on a transition the
subject's delta goes to every viewer in its directional `presence_audience`
(the inverse of `presence_visible_scope`), so even *asymmetric* visibility
(manager-sees-report-but-not-vice-versa) is exact — at O(audience) broadcasts
per transition. `:broadcast` instead streams one shared account stream and
pushes deltas instantly, with **no** visibility filtering (open-visibility
accounts only); pair it with the client `filter` option below for *cosmetic*
per-viewer hiding.

```jsx
// :broadcast + cosmetic client filter (NOT a security boundary — the full
// roster still reaches the client; use a server-side mode to truly enforce).
const { online } = usePresenceRoster({ filter: (m) => canISee(m.id) });
```

See `docs/PRESENCE_ROSTER_PLAN.md` for the full mode matrix and tradeoffs.

**Per-device, multi-session.** A subject's state is aggregated across *all*
their live sessions (multiple browser tabs, mobile, etc.):

```
{ id: 7, status: "active", devices: { web: "idle", mobile: "active" } }
```

- `status` — highest activity across devices (the "active anywhere?" answer):
  - `active` — a live session is visible/foreground **and** working
  - `idle` — a live session is visible/foreground but not actively using
  - `background` — only backgrounded/hidden sessions are live
  - `offline` — no live sessions
- `devices[platform]` — that platform's own status (answers "active on
  **mobile**?" vs. "active at all?").

#### Configure

```ruby
WhereIsWaldo.configure do |config|
  # The org/account a subject belongs to. Required to enable the roster.
  config.presence_org = ->(subject) { subject.account }

  # What a VIEWER may see (:pull/:nudge/:fanout). Any visibility rule,
  # server-enforced. Defaults to the viewer's whole org when unset.
  config.presence_visible_scope = ->(viewer) { viewer.visible_users }

  # Who may see a SUBJECT — the inverse of presence_visible_scope. Only needed
  # for :fanout (enables instant push under asymmetric visibility).
  config.presence_audience = ->(subject) { subject.visible_to_users }

  # Delivery mode, per account. Symbol or a callable resolving account -> mode.
  # MUST be a function of the account (uniform for all its members). Default :pull.
  config.roster_mode = ->(account) { account.everyone_admin? ? :broadcast : :pull }

  # :broadcast only — the member list for the shared snapshot. Defaults to
  # org.public_send(<subjects>) inferred from subject_class (e.g. :users).
  config.presence_roster = ->(org) { org.users.active }

  # Tuning (:pull/:nudge)
  config.roster_poll_interval = 15  # seconds
  config.roster_cache_ttl     = 90  # seconds; > poll gap → auto-resync
end
```

The `RosterChannel` is provided by the gem; no app code is needed beyond config.

#### Consume it (React — data hook, bring your own UI)

```jsx
import { usePresenceRoster, presenceColor, memberLabel } from '@byscott-io/where-is-waldo';

function TeamPresence() {
  const { online, members, onlineCount, byId } = usePresenceRoster();

  // `members` is always the full, live set (snapshot seeded, deltas patched).
  return (
    <ul>
      {online.map((m) => (
        <li key={m.id}>
          <span style={{ color: presenceColor(m.status) }}>●</span>
          {memberLabel(m)} — {m.status}
          {m.devices.mobile && ' 📱'}
        </li>
      ))}
    </ul>
  );
}
```

The hook and its reducer (`../core/rosterStore`) are pure — **no DOM** — so a
React Native app reuses the exact same data logic and only swaps the view.

#### Query presence server-side

```ruby
WhereIsWaldo.roster_snapshot(org)            # full roster + per-device state
WhereIsWaldo.roster_state_for(user.id)       # => { status:, devices: }
WhereIsWaldo.presence_on(user.id, :mobile)   # => "idle" (per-device)
```

#### Reporting presence from mobile

Mobile is "logged in" purely by connecting with `metadata: { platform: "mobile" }`
and sending the same heartbeat shape as the web client. The heartbeat/activity
state machine lives in a DOM-free core, `createPresenceReporter`, that the web
`usePresence` hook wraps — a React Native app reuses the **same core** and only
swaps the sensors: map app foreground/background to `setVisible`, and touches to
`reportActivity`. No server-side changes; `platform` is read from the metadata
(defaults to `"web"`).

```jsx
// React Native reporter — same core, native sensors.
import { useEffect, useRef } from 'react';
import { AppState, PanResponder } from 'react-native';
import { createPresenceReporter, configureCable } from '@byscott-io/where-is-waldo';

configureCable({ url: WS_URL, getToken: () => token });

export function usePresenceNative() {
  const reporterRef = useRef(null);

  useEffect(() => {
    const reporter = createPresenceReporter({ metadata: { platform: 'mobile' } });
    reporterRef.current = reporter;
    reporter.start();
    reporter.setVisible(AppState.currentState === 'active');

    const sub = AppState.addEventListener('change', (s) =>
      reporter.setVisible(s === 'active'),
    );
    return () => {
      sub.remove();
      reporter.stop();
    };
  }, []);

  // Feed touches as activity (attach these handlers to your root view).
  const pan = useRef(
    PanResponder.create({
      onStartShouldSetPanResponderCapture: () => {
        reporterRef.current?.reportActivity();
        return false; // observe only; don't capture the gesture
      },
    }),
  ).current;

  return pan.panHandlers;
}
```

`createPresenceReporter` is pure JS (no DOM), and `@rails/actioncable` works on
React Native with the built-in `WebSocket` — so the reporter, the roster hook
(`usePresenceRoster`), and the roster reducer all run unchanged on mobile; only
the sensors and the view are platform-specific.

### Client Event Subscriptions

Components subscribe to a raw event **type** with the `useWaldoEvent` hook,
receive the payload, and decide for themselves whether it's relevant. The
subscription auto-unsubscribes on unmount — there is no central handler
registry. Adding a new event = a server `broadcast_to` + a `useWaldoEvent`
call in whatever component cares.

```jsx
import { useWaldoEvent } from '@byscott-io/where-is-waldo';

function ChatRoom({ roomId }) {
  // Single type — filter the payload yourself
  useWaldoEvent('chat_message', (data) => {
    if (data.room_id === roomId) addMessage(data);
  });

  // Many types at once. useWaldoEvent is a pure subscription — to coalesce a
  // burst into one call, compose a debounce at the call site (e.g. corebyscott's
  // useDebouncedCallback): const refetch = useDebouncedCallback(loadAll, 250);
  useWaldoEvent(['notification', 'data_refresh'], refetch);

  return null;
}
```

For a non-React / imperative context, `subscribeToEvent(type, cb)` returns an
unsubscribe function:

```js
import { subscribeToEvent } from '@byscott-io/where-is-waldo';

const unsubscribe = subscribeToEvent('chat_message', (data) => addMessage(data));
// later: unsubscribe();
```

### React Hooks

```jsx
import { usePresenceContext } from '@byscott-io/where-is-waldo';

function StatusIndicator() {
  const { connected, tabVisible, subjectActive } = usePresenceContext();

  return <span>{connected ? 'Online' : 'Offline'}</span>;
}
```

### Cleanup Job

```ruby
# For database adapter - schedule cleanup of stale records
# config/initializers/sidekiq.rb
Sidekiq::Cron::Job.create(
  name: 'Presence cleanup',
  cron: '*/5 * * * *',
  class: 'WhereIsWaldo::PresenceCleanupJob'
)
```

### Version Management

```bash
rake version:show         # Show current version
rake version:bump[0.1.0]  # Bump gem and npm together
```

## Security

ActionCable presence is only as safe as the connection auth around it. What the
gem guarantees, and what your app must do:

**Guaranteed by the gem**

- **No client-chosen rooms.** `RosterChannel` derives the org from the
  *authenticated connection* (`current_subject` → `presence_org`), never from a
  client-supplied param — a user cannot subscribe to another org's roster.
- **Self-scoped subject streams.** `PresenceChannel` streams only the
  connection's own subject id, so targeted messages can't be eavesdropped.
- **Unauthenticated connections are rejected** (`JwtConnection`).

**Your app's responsibility**

- **Identify the connection from a *verified* credential** (a signed JWT, as
  `JwtConnection` does). Never trust a client-supplied `subject_id`. ⚠️ The
  dummy app authenticates from a query param for tests only — do not copy that
  into production.
- **`subject_data_proc` fans out org-wide.** Every field it returns is
  broadcast to all roster members. Include only what all members may see; keep
  PII out unless intended.
- **Visibility enforcement depends on the delivery mode.** `:pull`, `:nudge`,
  and `:fanout` enforce server-side — `:pull`/`:nudge` by `presence_visible_
  scope` (a `WHERE ... IN` clause), `:fanout` by `presence_audience` — so
  nothing an unauthorized member could read off the wire. `:broadcast` does
  **no** filtering: it shares one account stream and pushes every member's
  presence to everyone (`presence_roster` only scopes the initial *snapshot
  list*, not the live stream). The client `filter` option is **cosmetic** — the
  full data still reaches the client — so it is not an access-control boundary.
  Select `:broadcast` (± client filter) only for genuinely open-visibility
  accounts; for any restricted visibility use a server-side mode (`:pull` is the
  default). See `docs/PRESENCE_ROSTER_PLAN.md` for the full mode matrix.
- **Token in the URL.** The JWT is passed as `?token=…`; use WSS only, keep
  tokens short-lived, and avoid logging query strings. Set
  `config.action_cable.allowed_request_origins` as defense-in-depth.
- **Heartbeat/DoS.** Heartbeats are client-paced DB writes; roster broadcasts
  are gated to transitions. For large or hostile deployments use the Redis
  adapter and consider rate-limiting.

## License

MIT
