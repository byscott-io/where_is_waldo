# WhereIsWaldo

Real-time presence tracking library for Rails + React using ActionCable.

## Project Structure

```
where_is_waldo/
├── lib/                          # Gem core
│   ├── where_is_waldo.rb         # Main module, delegated API
│   ├── where_is_waldo/
│   │   ├── configuration.rb      # Config options
│   │   ├── engine.rb             # Rails engine
│   │   └── version.rb            # Reads from VERSION file
│   └── generators/               # Install generator
├── app/
│   ├── channels/                 # ActionCable channel
│   ├── models/                   # Presence model
│   ├── services/                 # PresenceService, Broadcaster, Adapters
│   └── jobs/                     # Cleanup job
├── src/                          # NPM package (React)
│   ├── cable/                    # ActionCable consumer + handlers
│   ├── context/                  # PresenceProvider
│   └── hooks/                    # usePresence hook
├── VERSION                       # Single source for gem + npm version
├── Rakefile                      # Version management tasks
└── package.json                  # NPM config
```

## Key Concepts

- **Subject**: The entity being tracked (User, Member, Student, etc.) - configurable
- **Session**: A unique connection (tab/device) - identified by session_id
- **No "room" concept**: Grouping is done via AR scopes, not a room column

## Main API

### Server (Ruby)

```ruby
# Queries
WhereIsWaldo.online(scope)              # AR relation of online subjects
WhereIsWaldo.online_ids(scope)          # Array of IDs
WhereIsWaldo.subject_online?(id)        # Boolean
WhereIsWaldo.sessions_for_subject(id)   # Array of session hashes

# Broadcasting
WhereIsWaldo.broadcast_to(scope, :type, data)
WhereIsWaldo.broadcast_to_online(scope, :type, data)
WhereIsWaldo.broadcast_to_session(session_id, :type, data)

# Presence management (usually automatic via channel)
WhereIsWaldo.connect(session_id:, subject_id:, metadata:)
WhereIsWaldo.disconnect(session_id:) or (subject_id:)
WhereIsWaldo.heartbeat(session_id:, tab_visible:, subject_active:)
```

### Client (React)

```jsx
// Configure the connection (presence + event subscriptions)
configureCable({
  url: '/cable',
  getToken: () => token,
});

// Provider wraps app (opens the cable + presence subscription once)
<PresenceProvider><App /></PresenceProvider>

// Subscribe to a real-time event type from ANY component. The component
// receives the payload, decides whether it's relevant, and auto-unsubscribes
// on unmount. Adding an event = an AR broadcast_to + a useWaldoEvent call;
// no central handler config.
useWaldoEvent('message_type', (data) => handle(data));

// One subscription across many types. To debounce, compose at the call site
// (e.g. corebyscott useDebouncedCallback): const refetch = useDebouncedCallback(loadAll, 250);
useWaldoEvent(['issue_update', 'project_update'], refetch);

// Hook for presence state
const { connected, tabVisible, subjectActive } = usePresenceContext();
```

## Configuration Options

| Option | Description |
|--------|-------------|
| `adapter` | `:database` or `:redis` |
| `table_name` | Presence table name |
| `session_column` | Column for session ID |
| `subject_column` | Column for subject ID (user_id, member_id, etc.) |
| `subject_class` | Model class name ("User", "Member") |
| `subject_data_proc` | Lambda to build subject data hash |
| `timeout` | Seconds until considered offline |
| `authenticate_proc` | Lambda to auth WebSocket connections |

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

12. **Fanout** — bump BOTH gem and npm in every consuming app (see
    [[waldo-fanout-both-gem-and-npm]]): per app `bundle update --conservative
    where_is_waldo` + `yarn upgrade @byscott-io/where-is-waldo`, build/lint-gated,
    stage lockfiles only, commit + push. Then deploy each (serialized queue).
13. **VERIFY THE DEPLOY — don't stop at the version number.** Confirm the new
    behavior actually appears in a real prod payload, not just that the gem
    version bumped. Use prod console (issuesbyscott configures the roster:
    `PRIMARY_HOST=52.72.207.102 ./scripts/app-console.sh issuesbyscott '<ruby>'`)
    and assert both: `WhereIsWaldo::VERSION == X.Y.Z` AND the feature is live in a
    payload with a real value — e.g. for the 0.1.7 `last_activity` release:
    ```ruby
    m = WhereIsWaldo::Roster.snapshot(Account.first).find { |x| x[:last_activity] }
    # => {id:, status:, devices:, last_activity: "2026-…Z"}  # real ISO timestamp, not just the key
    ```
    A green `deployment_synced` monitor only proves the sha shipped — it does NOT
    prove the feature works. Exercise the actual code path.

## Adapters

- **DatabaseAdapter**: Uses ActiveRecord, requires cleanup job
- **RedisAdapter**: Uses Redis with TTL, auto-expires
