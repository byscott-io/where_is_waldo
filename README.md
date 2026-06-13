# WhereIsWaldo

Real-time presence tracking for Rails + React using ActionCable.

## Features

- **Presence tracking** - know who's online
- **Scope-based queries** - `online(org.users.admin)`
- **Targeted broadcasting** - send to any AR scope
- **Event subscriptions** - components subscribe by event type (`useWaldoEvent`)
- **Activity monitoring** - tab visibility, user activity
- **Multi-session** - same user, multiple tabs/devices
- **Flexible storage** - database or Redis

## Quickstart

### 1. Install

```ruby
# Gemfile
gem 'where_is_waldo', github: 'byscott-io/where_is_waldo'
```

```bash
# Database adapter (default)
rails generate where_is_waldo:install --subject_column=user_id
rails db:migrate

# Redis adapter (no migration needed)
rails generate where_is_waldo:install --adapter=redis --subject_column=user_id
```

```bash
npm install @byscott-io/where-is-waldo @rails/actioncable
```

### 2. Configure

```ruby
# config/initializers/where_is_waldo.rb
WhereIsWaldo.configure do |config|
  config.subject_class = "User"
  config.authenticate_proc = ->(request) {
    # Return user_id from your auth token
    decode_token(request.params[:token])[:user_id]
  }
end
```

```jsx
// app.jsx — configure the connection once, wrap the app
import { configureCable, PresenceProvider } from '@byscott-io/where-is-waldo';

configureCable({
  url: '/cable',
  getToken: () => localStorage.getItem('token'),
  presence: {
    debug: true,  // Enable console logging for troubleshooting
  },
});

<PresenceProvider>
  <App />
</PresenceProvider>
```

```jsx
// any component — subscribe to an event type and filter the payload yourself.
// Auto-unsubscribes on unmount; no central handler config.
import { useWaldoEvent } from '@byscott-io/where-is-waldo';

function Notifications() {
  useWaldoEvent('notification', (data) => showToast(data.message));
  useWaldoEvent('force_logout', () => logout());
  return null;
}
```

### 3. Use

```ruby
# Query who's online
WhereIsWaldo.online(org.users)           # => AR relation
WhereIsWaldo.online(org.users.admin)     # => filter by scope
WhereIsWaldo.subject_online?(user.id)    # => true/false

# Broadcast messages
WhereIsWaldo.broadcast_to(org.users, :notification, { message: "Hello!" })
WhereIsWaldo.broadcast_to(user, :force_logout, { reason: "Password changed" })
```

---

## Detailed Documentation

### Server Configuration

```ruby
WhereIsWaldo.configure do |config|
  config.adapter = :database            # or :redis
  config.table_name = "presences"
  config.session_column = :session_id
  config.subject_column = :user_id      # or :member_id, :student_id
  config.subject_class = "User"         # or "Member", "Student"

  config.timeout = 90                   # seconds until offline
  config.heartbeat_interval = 30

  # Optional: custom subject data in presence hash
  config.subject_data_proc = ->(user) {
    { id: user.id, name: user.name, avatar: user.avatar_url }
  }

  # Redis adapter
  # config.redis_client = Redis.new(url: ENV["REDIS_URL"])
end
```

### Querying Presence

```ruby
# Get online subjects from any AR scope
WhereIsWaldo.online(org.users)
WhereIsWaldo.online(User.where(role: "admin"))
WhereIsWaldo.online(classroom.students)

# Get just IDs
WhereIsWaldo.online_ids(org.users)

# Check specific subject
WhereIsWaldo.subject_online?(user.id)

# Get all sessions for a subject
WhereIsWaldo.sessions_for_subject(user.id)
# => [{ session_id: "...", tab_visible: true, subject_active: false, ... }]
```

### Broadcasting

```ruby
# To any AR scope
WhereIsWaldo.broadcast_to(org.users, :notification, { message: "Hi" })
WhereIsWaldo.broadcast_to(org.users.admin, :alert, { level: "warning" })

# Only to online subjects
WhereIsWaldo.broadcast_to_online(org.users, :update, { data: "..." })

# To a single subject (all their sessions)
WhereIsWaldo.broadcast_to(user, :force_logout, {})

# To a specific session
WhereIsWaldo.broadcast_to_session(session_id, :warning, { message: "..." })
```

### Client Event Subscriptions

Components subscribe to a raw event **type** with the `useWaldoEvent` hook,
receive the payload, and decide for themselves whether it's relevant. The
subscription auto-unsubscribes on unmount — there is no central handler
registry. Adding a new event = a server `broadcast_to` + a `useWaldoEvent`
call in whatever component cares.

```jsx
import { useWaldoEvent } from '@byscott-io/where-is-waldo';

function ChatRoom({ roomId }) {
  // Single type — filter the payload yourself
  useWaldoEvent('chat_message', (data) => {
    if (data.room_id === roomId) addMessage(data);
  });

  // Many types coalesced into one debounced handler (single internal timer)
  useWaldoEvent(['notification', 'data_refresh'], refetch, { debounce: 250 });

  return null;
}
```

For a non-React / imperative context, `subscribeToEvent(type, cb)` returns an
unsubscribe function:

```js
import { subscribeToEvent } from '@byscott-io/where-is-waldo';

const unsubscribe = subscribeToEvent('chat_message', (data) => addMessage(data));
// later: unsubscribe();
```

### React Hooks

```jsx
import { usePresenceContext } from '@byscott-io/where-is-waldo';

function StatusIndicator() {
  const { connected, tabVisible, subjectActive } = usePresenceContext();

  return <span>{connected ? 'Online' : 'Offline'}</span>;
}
```

### Cleanup Job

```ruby
# For database adapter - schedule cleanup of stale records
# config/initializers/sidekiq.rb
Sidekiq::Cron::Job.create(
  name: 'Presence cleanup',
  cron: '*/5 * * * *',
  class: 'WhereIsWaldo::PresenceCleanupJob'
)
```

### Version Management

```bash
rake version:show         # Show current version
rake version:bump[0.1.0]  # Bump gem and npm together
```

## License

MIT
