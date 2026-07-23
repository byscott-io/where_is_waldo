# Changelog

Notable changes to where_is_waldo. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

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
