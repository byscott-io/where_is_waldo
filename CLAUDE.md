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

// One subscription across many types, debounced:
useWaldoEvent(['issue_update', 'project_update'], refetch, { debounce: 250 });

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

## Adapters

- **DatabaseAdapter**: Uses ActiveRecord, requires cleanup job
- **RedisAdapter**: Uses Redis with TTL, auto-expires
