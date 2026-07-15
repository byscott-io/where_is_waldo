# Presence Roster — Multi-Mode Delivery Plan

Live presence awareness ("who's around in my org/account, on what device, how
active") for a **public** gem — so the design must handle the full mixture of
visibility rules (open, group, role, ACL; symmetric **and** asymmetric) and let
each consumer trade **latency × cost × visibility-enforcement** to fit their app.

The key architectural idea: **one shared data model and client reducer; a
pluggable server-side delivery strategy, selectable per account.**

---

## 1. Delivery modes (the menu)

Selected by a per-account resolver (see §4). `:pull` is the safe default.

| Mode | Latency | Visibility enforcement | Cost / transition | Use when |
|------|---------|------------------------|-------------------|----------|
| **`:pull`** | ~poll interval (e.g. 5–30s) | Server-side query (`WHERE IN visible_scope`) — **any** rule, incl. asymmetric | Flat: 1 cached query per heartbeat/poll per session | Latency tolerable; arbitrary visibility; simplest & safest |
| **`:nudge`** | Near-instant | Server-side query (same as pull) | O(1) content-free broadcast → each viewer filtered-pulls | Low latency **and** restricted visibility (the usual restricted answer) |
| **`:broadcast`** | Instant | **None** (everyone in account sees everyone) | O(1) broadcast to one account stream | Account has genuinely open visibility (e.g. all admins) |
| **`:broadcast` + client filter** | Instant | **Cosmetic only** (client hides; full data on wire) | O(1) | Consumer explicitly accepts insider visibility of raw payload |
| **`:fanout`** | Instant | Server-side per-viewer | O(audience) broadcasts | Low latency + restricted visibility **and** even "activity is happening" timing must be hidden |

Notes:
- `:pull` and `:nudge` filter identically (server query); `:nudge` just adds an
  O(1) content-free trigger so clients re-poll immediately instead of waiting
  for the next interval.
- `:broadcast` does **no** filtering — it is the everyone-sees-everyone fast
  path. The optional client filter makes hiding *cosmetic* (insiders can read
  the pre-filter payload); it is an explicit, documented opt-in.
- `:fanout` is the only mode that pushes protected data per-viewer; it exists
  solely for the narrow "hide even the timing signal" case. `:nudge` dominates
  it otherwise (cheaper, equally correct).

---

## 2. Two-axis mental model

- **Axis 1 — latency need (consumer's call):** acceptable → `:pull`; low → a push
  mode.
- **Axis 2 — visibility (only for push):** open account → `:broadcast`;
  restricted account → `:nudge` (default) or `:fanout` (timing-sensitive).

`:pull` needs no visibility sub-switch because it filters server-side regardless.

---

## 3. Shared layer (mode-agnostic — mostly built already)

- **Aggregation** — sessions → per-subject `{ status, devices }`, highest
  activity across all sessions, per-device roll-up. (`WhereIsWaldo::Roster`,
  already implemented + tested.)
- **Wire message contracts** (identical across modes so the client reducer never
  forks):
  - `roster_snapshot { mode, poll_interval, members: [ { id, status, devices, ...subject_data } ] }`
  - `roster_delta { member: { id, status, devices, ...subject_data } }`
  - `roster_nudge {}` — content-free (nudge mode only)
  - client → server action: `poll` (pull/nudge modes)
- **Client reducer** — `applyRosterMessage` (snapshot seeds map, delta patches,
  offline kept) + `sortedMembers` / `onlineMembers` / `deviceStatus` /
  `memberLabel` / `presenceColor`. Pure JS, no DOM → shared with mobile.
  (Already implemented in `src/core/rosterStore.js`.)

---

## 4. Config surface (server) — single source of truth

```ruby
WhereIsWaldo.configure do |config|
  # --- Identity & membership ---
  # The account/org a subject belongs to. Keys per-account behavior + streams.
  config.presence_org = ->(subject) { subject.account }

  # What a viewer MAY SEE (for pull/nudge/fanout snapshots + pull diffs).
  # AR scope of subjects. Defaults to presence_org's members if unset.
  config.presence_visible_scope = ->(viewer) { viewer.visible_users }

  # Who may SEE a subject (ONLY needed for :fanout). AR scope of viewers.
  # Must be the exact inverse of presence_visible_scope.
  config.presence_audience = ->(subject) { subject.visible_to_users }

  # For :broadcast (open) — member list for the shared snapshot.
  # Defaults to org.<subjects> inferred from subject_class.
  config.presence_roster = ->(org) { org.users }

  # --- Delivery strategy (per account) ---
  # Symbol OR a callable resolving an account -> mode. MUST be a function of the
  # ACCOUNT (uniform for all its members), never per-user. Default: :pull (safe).
  config.roster_mode = ->(account) do
    account.everyone_admin? ? :broadcast : :nudge
  end

  # --- Tuning ---
  config.roster_poll_interval = 15          # seconds (pull/nudge)
  config.roster_cache_ttl     = 90          # seconds; > max poll gap → resync
  config.roster_nudge_jitter  = 0.5         # seconds; herd control on nudge
end
```

**Contracts / invariants (enforced by docs + tests):**
1. `roster_mode` resolves per **account**, uniformly — mixing modes within one
   account breaks pub/sub alignment.
2. `presence_audience` and `presence_visible_scope` must be exact inverses
   (`v ∈ audience(x) ⟺ x ∈ visible_scope(v)`).
3. `:broadcast` performs **no** server-side visibility filtering. Selecting it
   asserts the account is open-visibility.
4. Default mode is the **safe** one (`:pull`); fast/leaky paths are opt-in.

---

## 5. Server architecture

### 5.1 Strategy interface

```ruby
module WhereIsWaldo::RosterDelivery
  class Base
    def on_subscribe(channel, subject); end   # RosterChannel#subscribed
    def on_poll(channel, subject); end         # RosterChannel#poll (pull/nudge)
    def on_transition(subject_id); end         # PresenceChannel transition hook
  end
end
```

Implementations:
- **`Broadcast`** — `on_subscribe`: `stream_from account_stream`, transmit
  snapshot (full `presence_roster`, or `visible_scope` when a client filter is
  advertised). `on_transition`: broadcast `roster_delta` to `account_stream`.
  `on_poll`: n/a.
- **`Pull`** — `on_subscribe`: transmit initial snapshot (`visible_scope`),
  seed cache baseline. `on_poll`: read baseline from `Rails.cache`
  (`waldo:roster:baseline:<session_id>`), compute current `visible_scope`
  states, diff → transmit `roster_delta`s (or full `roster_snapshot` on cache
  miss/stale = resync), rewrite baseline. `on_transition`: n/a.
- **`Nudge < Pull`** — same as Pull, plus `on_transition`: broadcast
  content-free `roster_nudge` to `account_stream`. Clients re-poll (jittered).
  `on_subscribe` also `stream_from account_stream` (for nudges only).
- **`Fanout`** — `on_subscribe`: `stream_from viewer_stream(subject)`, transmit
  snapshot (`visible_scope`). `on_transition`: for each `v ∈ audience(subject)`
  broadcast `roster_delta` to `viewer_stream(v)`.

### 5.2 Mode resolution
`RosterMode.for(account)` memoized per connection; consulted by **both**
channels (RosterChannel for subscribe/poll; PresenceChannel for the transition
hook) so they always agree. Strategy instance chosen from the resolved mode.

### 5.3 Channels
- **`RosterChannel`**: `subscribed` → resolve mode → `strategy.on_subscribe`.
  New `poll` action → `strategy.on_poll`. Rejects if no org (unchanged).
- **`PresenceChannel`**: existing transition gate (connect / disconnect /
  active↔idle / tab flip) → `strategy.on_transition(subject_id)`. (Gate already
  built; only the callee changes from the hard-coded broadcast to the strategy.)

### 5.4 Cache (pull/nudge)
- Backend: `Rails.cache` (Redis in prod; consistent with the Redis adapter).
- Key: `waldo:roster:baseline:<session_id>` (per **session/tab**, not per viewer
  — independent delta cursors).
- Value: last-sent member-state map `{ id => { status, devices } }`.
- TTL = `roster_cache_ttl`; expiry → next poll is a full snapshot (self-healing
  resync). Removals detected by diff (no soft-delete / schema migration needed).

### 5.5 Stream names
- `where_is_waldo:roster:account:<Account>:<id>` — broadcast + nudge
- `where_is_waldo:roster:viewer:<id>` — fanout
- (pull uses no stream — data rides the `poll` transmit)

---

## 6. Client architecture (React + shared core; mobile parity)

`usePresenceRoster` reads the **server-declared** `mode` + `poll_interval` from
the first `roster_snapshot` and adapts — no separate client mode config:

- `:broadcast` / `:nudge` / `:fanout`: subscribe + `received` → reducer.
- `:pull` / `:nudge`: run a jittered interval calling `perform('poll')`.
- `:broadcast` + filter: apply consumer-supplied `filter(member)` in the reducer
  (cosmetic; documented).
- Shared reducer (`core/rosterStore`) unchanged; only the transport wrapper
  differs. React Native reuses the core + a poll loop, swapping only the view.

Client option:
```js
usePresenceRoster({ filter: (m) => canISee(m) }) // only honored in :broadcast
```

---

## 7. Security model (per mode)

| Mode | Enforced where | Insider can see hidden users? |
|------|----------------|-------------------------------|
| `:pull` / `:nudge` / `:fanout` | Server (query / audience) | No |
| `:broadcast` (open) | N/A — open by definition | N/A |
| `:broadcast` + client filter | Client only | **Yes** (cosmetic) |

Plus the connection-level guarantees already documented in the README Security
section (server-derived org, self-scoped subject streams, JWT auth, `subject_
data_proc` fans out to whatever the *effective* audience is — for broadcast that
is the whole account).

---

## 8. Refactor of what already exists

Currently built = the `:broadcast` mode for a single open account
(`presence_org` + shared stream + `usePresenceRoster` + specs). Migration:
- Extract the current publish path into `RosterDelivery::Broadcast`.
- Keep `WhereIsWaldo::Roster` as the mode-agnostic aggregation/snapshot service.
- Add the mode resolver + strategy dispatch in both channels.
- No DB migration required (pull uses cache-map diffs, not tombstones).

---

## 9. Test matrix

- **Aggregation** (done): per-device roll-up, multi-session, background/idle/offline.
- **Mode resolver**: symbol vs callable; per-account uniformity; default `:pull`.
- **Broadcast**: shared-stream subscribe + transmit; transition → account delta;
  client filter cosmetic (reducer-level).
- **Pull**: cache miss → snapshot; hit → delta; offline via diff; stale → resync;
  **visibility change mid-session** emits correct adds/removals; per-session key
  isolation (two tabs independent cursors).
- **Nudge**: transition → content-free nudge (no PII on wire); client re-poll;
  jitter.
- **Fanout**: audience fan-out; **asymmetric** correctness (A sees B, B not A).
- **Channel security**: cannot subscribe to another account's roster.
- **Client**: mode adaptation (listen vs poll), reducer patching, filter.

---

## 10. Staging & rollout

- **Phase 1 — foundation + the two anchors.** Strategy abstraction + resolver;
  `:broadcast` (refactor of existing) + `:pull` (cache-diff). Covers "open
  account instant" and "acceptable-latency arbitrary visibility." Ship + version
  bump.
- **Phase 2 — low-latency restricted.** `:nudge` (Pull + content-free trigger,
  jitter). Ship + bump.
- **Phase 3 — edge cases.** `:fanout` (audience) + `:broadcast` client-filter
  option. Ship + bump.
- **Mobile** (task #19): DOM-free presence-reporter core + RN reporter, reuses
  the shared core + poll loop.
- **Publish** to npm (`@byscott-io/where-is-waldo`) + the gem, **new version**,
  after each phase (or at the end) — WAIT for CI green before publishing.

Rough effort: Phase 1 ≈ 2–3 days; Phase 2 ≈ +0.5–1 day; Phase 3 ≈ +1 day;
mobile ≈ +1 day. Docs/tests included per phase.

---

## 11. Open decisions (need consumer/owner input)

1. **Default `poll_interval`** (freshness vs query load): 15s? 10s?
2. **`roster_cache_ttl`** relative to interval (resync window): ~6× interval?
3. **Nudge jitter window** (herd control): 0.5s? scale with account size?
4. **Config key names** — `presence_org` / `presence_visible_scope` /
   `presence_audience` / `roster_mode` — final?
5. **Client filter**: flag on `:broadcast`, or its own mode name for louder
   intent (e.g. `:broadcast_client_filtered`)?
6. **Default mode** confirm `:pull` (safe) vs `:broadcast` (back-comptible with
   what's built).
