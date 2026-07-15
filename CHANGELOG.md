# Changelog

Notable changes to where_is_waldo. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

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
