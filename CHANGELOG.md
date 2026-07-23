# Changelog

Notable changes to where_is_waldo. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

## 0.1.4

### Fixed

- **Roster reads now route through the configured adapter.** Previously
  `Roster.states_for` (which powers `state_for`, `snapshot`, `members_for`,
  every roster delta) queried the `Presence` ActiveRecord model directly.
  Under `adapter = :redis`, writes went to Redis but reads hit an empty (or
  absent) database table — presence dots stayed grey no matter how many
  heartbeats came in. `Roster` now calls `PresenceService.sessions_for_subjects`
  which delegates to whichever adapter is configured, so writes and reads
  share one store on every adapter.

### Added

- `Adapters::Base#sessions_for_subjects(subject_ids, timeout:)` — bulk-read
  live sessions grouped by subject id, with a correct-but-unoptimized default
  implementation that fans out over `sessions_for_subject`. `DatabaseAdapter`
  overrides it with a single bulk query (`Presence.where(subject_col => ids)`
  + `includes(:subject)`); `RedisAdapter` overrides with per-subject reads
  filtered by heartbeat threshold. Timeout defaults to `config.timeout`.
- `PresenceService.sessions_for_subjects` — public delegate so callers stay
  off the adapter directly.
- `Configuration#suppress_presence_proc` — callable that decides, per
  connection, whether to skip presence registration for that subscriber.
  Receives the ActionCable connection; returns truthy to suppress. A
  suppressed subscriber still subscribes normally (streams from
  `where_is_waldo:subject:<id>`, receives broadcasts, can invoke channel
  actions) — they just don't register a Presence row / heartbeat / roster
  transition. Use for cases where the WebSocket session is legitimate but
  shouldn't be counted as "the subject is present" (e.g. support-user
  impersonation tabs).

  ```ruby
  config.suppress_presence_proc = ->(connection) {
    connection.request.session[:su_user].present?
  }
  ```

### Changed

- `Roster.aggregate` / `session_level` / `platform` now consume presence
  hashes (`session[:tab_visible]`, `session[:metadata]`) — matching the
  shape every adapter already returned — instead of ActiveRecord `Presence`
  method calls. No behavior change for callers; existing per-device and
  per-subject aggregation semantics preserved.

## 0.1.3

### Fixed

- Require `action_cable/engine`, `active_job/railtie` and
  `active_record/railtie` from the engine. The engine's `app/*` classes name
  these frameworks in a **superclass** position — `ApplicationCable::Channel <
  ActionCable::Channel::Base`, `ApplicationJob < ActiveJob::Base`,
  `ApplicationRecord < ActiveRecord::Base` — so they resolve at load time, and
  `Rails::Engine` eager loads every `app/*` directory. A host that skipped any
  of those railties (`rails new --skip-action-cable` being the common case)
  therefore died at boot with `NameError: uninitialized constant
  WhereIsWaldo::ApplicationCable::ActionCable`. The engine now loads what it
  subclasses instead of depending on the host's `application.rb`. Affects every
  released version up to and including `0.1.2`.

  `spec/dummy` now requires none of the three itself, so the suite fails loudly
  if this regresses.

## 0.1.2

### Fixed

- Drop the manual `config.autoload_paths <<` lines for `app/services`,
  `app/channels`, `app/jobs`, and `app/models` from the engine. `Rails::Engine`
  already globs every `app/*` directory into the engine's autoload **and**
  eager-load paths, so the entries were pure duplication.

  (An earlier wording of this entry claimed the entries also suppressed eager
  loading of those directories. That was wrong: `Rails::Engine`'s own
  `paths.eager_load` still listed all four either way, so the eager-loaded set
  was identical before and after. The change is a cleanup, not a behaviour fix.)

### Security (development dependencies only)

- `axios` → `1.18.0`+ (via a `resolutions` pin; reached only through
  `start-server-and-test` → `wait-on`) and `loofah` → `2.25.2`. Neither is
  shipped in the published gem or npm package — the npm package declares no
  runtime `dependencies` — so released `0.1.1` artifacts were not affected.

## 0.1.1

### Fixed

- Package the `VERSION` file (and `CHANGELOG.md`) in the gem. `0.1.0`'s gemspec
  omitted `VERSION`, but `version.rb` reads it at load time, so the installed
  gem raised `Errno::ENOENT` on require and failed to boot. (npm `0.1.0` was
  unaffected — it reads its version from `package.json`.)

## 0.1.0

First release to public **npm** (`@byscott-io/where-is-waldo`) and **RubyGems**
(`where_is_waldo`).

### Added

- **Live presence roster** — per-device presence (`active` / `idle` /
  `background` / `offline`, aggregated across web, mobile, and multiple
  sessions), delivered as **data** via the `usePresenceRoster` hook (bring your
  own UI).
- **Pluggable per-account delivery** (`roster_mode`) — trade latency ×
  visibility × cost per account:
  - `:poll` — client polls; server replies with a server-filtered diff.
  - `:nudge` — `:poll` plus a content-free "re-poll" signal for near-instant refresh.
  - `:fanout` — instant per-viewer push (arbitrary/asymmetric visibility).
  - `:broadcast` — instant shared-stream push (open-visibility accounts).
- **Server-side visibility enforcement** via `roster_visible_to` (subjects a
  viewer may see) and `roster_viewers_of` (its inverse, for `:fanout`); org
  boundary via `roster_org`.
- **DOM-free presence reporter core** (`createPresenceReporter`) shared by the
  web `usePresence` hook and a React Native reporter (`metadata.platform`).
- Docs: mode decision guide (README) and `docs/SERVER_SIDE_SUBSCRIPTIONS.md`
  (future authorized pub/sub direction).

### Notes

- npm entry points now ship the built bundle (`dist/`); `@rails/actioncable` is
  a peer dependency (not bundled).
