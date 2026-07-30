# Claude review checklist — where_is_waldo

Repo-specific checks applied IN ADDITION to the standard fleet review. The
reviewer reports on each item. (Starter derived from CLAUDE.md "Release Process"
— edit freely; this is the single place to tune waldo's PR checks.)

## Release / deploy readiness
- If shipped code changed (`lib/`, `app/`, `src/`): is **VERSION** bumped, and do
  **package.json** and **Gemfile.lock** (`where_is_waldo (X.Y.Z)`) all match it?
- Is there a matching **`## X.Y.Z`** entry in **CHANGELOG.md**?
- If the public API, roster payload, or config changed: is **README.md** updated?
  (It renders on both npm and GitHub — stale docs ship to users.)
- New or changed behavior has **RSpec** coverage (a fail-then-pass proof spec for
  bug fixes).
- No secrets, keys, or master-key/`.env` values added to tracked files.

## Notes
- Docs-only PRs do **not** require a VERSION/CHANGELOG bump.
- A failed release-readiness item on a code PR should **escalate the verdict to
  request-changes**, even if the general review is otherwise clean.
