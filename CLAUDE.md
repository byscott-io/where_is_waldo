# WhereIsWaldo

Real-time presence tracking for Rails + React over ActionCable. Know who is
online, and push messages to any ActiveRecord scope, without an external service.

**This repo is public.** Anyone can read it and anyone can consume the library,
so write for that audience: no infrastructure detail, no internal hostnames, and
judge changes on their merits for any consumer rather than on what this fleet
happens to need.

## Ships

| Package | Registry | Version |
|---------|----------|---------|
| `where_is_waldo` (gem) | RubyGems (public) | 0.1.10 |
| `@byscott-io/where-is-waldo` (npm) | public npm, **and** GitHub Packages | 0.1.10 |

One `VERSION` file at the root drives both. The npm package is dual-published:
public npm is canonical, but the fleet's `.npmrc` resolves the whole
`@byscott-io` scope from GitHub Packages, so a release absent there is invisible
to consumers.

## Where the detail lives

| Task | Read |
|------|------|
| Using the library — install, config, API | [README.md](README.md) |
| Cutting a release | [docs/RELEASING.md](docs/RELEASING.md) |
| Presence roster design | [docs/PRESENCE_ROSTER_PLAN.md](docs/PRESENCE_ROSTER_PLAN.md) |
| Server-side subscriptions (proposed) | [docs/SERVER_SIDE_SUBSCRIPTIONS.md](docs/SERVER_SIDE_SUBSCRIPTIONS.md) |

The README is the usage documentation and is not duplicated here. It is also what
npm renders, so it must be correct before publishing.

Behaviour rules are in `.claude/rules/`.

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


## Adapters

- **DatabaseAdapter**: Uses ActiveRecord, requires cleanup job
- **RedisAdapter**: Uses Redis with TTL, auto-expires
