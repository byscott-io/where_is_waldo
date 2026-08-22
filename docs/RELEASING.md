# Releasing where_is_waldo

Maintainer notes. Usage documentation is in the [README](../README.md).

The gem and the npm package share one VERSION file at the repo root and release
together to three registries: RubyGems, public npm, and GitHub Packages.

## Version Management

Single VERSION file at root. Both gem (version.rb) and npm (package.json) use it.

```bash
rake version:bump[0.0.2]  # Updates both
```

## Release Process

**Publishes are immutable and one path renders docs — so update EVERYTHING
first, publish last.** npmjs.com renders the README from the published tarball
and only refreshes it on the *next* version, so a README that lags the code
stays stale on npm until the following release. rubygems.org does NOT render the
README (it shows `spec.summary`/`spec.description` + the metadata links), but the
gem still bundles it. Get docs right *before* you build/publish.

Do these **in order**; do not build or publish until steps 1–5 are committed:

1. **Bump version** — `rake version:bump[X.Y.Z]` (updates VERSION → gem +
   package.json). Confirm VERSION, `package.json`, and `Gemfile.lock`
   (`where_is_waldo (X.Y.Z)`) all match; run `bundle install` if the lock lags.
2. **CHANGELOG.md** — add the `## X.Y.Z` entry.
3. **README.md** — update for any API / roster-payload / config change. This is
   the one people read (GitHub + npm) — must be final before npm publish.
4. **Other docs** — `docs/*.md` (e.g. `PRESENCE_ROSTER_PLAN.md`) if the change
   touches them.
5. **Green + commit** — `bundle exec rspec`, `bundle exec rubocop`, `yarn build`
   (+ JS tests) all pass; commit steps 1–4 to master.
6. **Build the gem** — `bundle exec rake build` → `pkg/where_is_waldo-X.Y.Z.gem`.
   Use `rake build`, NOT `gem build` (which drops it at the repo root and breaks
   Scott's `gem push pkg/...` command).
7. **Publish npm (public)** — `yarn install && yarn build && npm publish`
   (public, `@byscott-io/where-is-waldo`). README is now final, so npm renders
   it right. This is the canonical public artifact.
8. **Dual-publish npm to GitHub Packages** — the fleet's `.npmrc` resolves the
   whole `@byscott-io` scope from `npm.pkg.github.com`, so consumers can only
   see the release if it's ALSO there (public npm stays canonical). Publish with
   a temp userconfig overriding the registry:
   ```
   printf '@byscott-io:registry=https://npm.pkg.github.com\n//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}\n' > .npmrc.ghpkg
   npm publish --userconfig .npmrc.ghpkg --registry https://npm.pkg.github.com
   rm .npmrc.ghpkg   # never commit it
   ```
9. **Tag** — `git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z`.
10. **Gem push is Scott's** — hand him `pkg/where_is_waldo-X.Y.Z.gem`; he runs
    `GEM_HOST_API_KEY="$RUBYGEMS_TOKEN" gem push pkg/where_is_waldo-X.Y.Z.gem`.
11. **Verify published** — all three registries show X.Y.Z:
    `gem list -r where_is_waldo`, `npm view @byscott-io/where-is-waldo version`
    (public), and `... --registry https://npm.pkg.github.com` (GH Packages).

### Roll out to the fleet (after publishing)

12. **Fanout** — bump BOTH the gem and the npm package in every consuming app.
    Per app: `bundle update --conservative where_is_waldo` and
    `yarn upgrade @byscott-io/where-is-waldo`, build- and lint-gated, staging
    lockfiles only, then commit and push. Deploy each afterwards.
13. **VERIFY THE DEPLOY — don't stop at the version number.** Confirm the new
    behaviour actually appears in a real production payload, not merely that the
    version bumped. From a production console on an app that configures the
    roster, assert both that `WhereIsWaldo::VERSION == X.Y.Z` AND that the
    feature is live with a real value — e.g. for the 0.1.7 `last_activity`
    release:
    ```ruby
    m = WhereIsWaldo::Roster.snapshot(Account.first).find { |x| x[:last_activity] }
    # => {id:, status:, devices:, last_activity: "2026-…Z"}  # real ISO timestamp, not just the key
    ```
    A green `deployment_synced` monitor only proves the sha shipped — it does NOT
    prove the feature works. Exercise the actual code path.

