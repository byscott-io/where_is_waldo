# Changelog

Notable changes to where_is_waldo. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

## 0.1.2

### Fixed

- Drop the manual `config.autoload_paths <<` lines for `app/services`,
  `app/channels`, `app/jobs`, and `app/models` from the engine. `Rails::Engine`
  already globs every `app/*` directory into the engine's autoload **and**
  eager-load paths, so the entries were redundant — and because
  `config.autoload_paths` is autoload-only, they marked those directories as
  not-eager-loadable, which can trip Zeitwerk in eager-loading (production)
  hosts. Zeitwerk still picks up all four directories.

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
