# Future: Server-Side Authorized Subscriptions

> Status: **idea / not built.** A future where_is_waldo feature, separate from the
> presence roster. Recorded here so the design isn't lost.

## The idea

A **true server-side subscription model**: when a component mounts, it tells the
server *"I'm interested in topic XYZ."* The server pushes changes for that topic
**only to subscribed clients**, and **authorizes** each subscription.

```
client (on mount):   subscribe("project:42:comments")
server:              (authorize) → stream_from "topic:project:42:comments"
server (on change):  broadcast_to_topic("project:42:comments", payload)
                     → delivered ONLY to authorized subscribers
client (on unmount): unsubscribe(...)   (or just disconnect)
```

## Why it's different from what exists today

Today the gem distributes events with **client-side interest filtering**:
`broadcast_to(scope, type, data)` fans a message to a whole scope (every client
on the scope receives it) and `useWaldoEvent(type, handler)` decides relevance in
JS. Simple, but two costs:

1. **Efficiency** — uninterested clients still receive the traffic (receive-and-
   ignore), rather than getting nothing.
2. **Security** — every client physically receives every type on the scope, so
   filtering is *cosmetic*. This is the same client-side-filter leak the roster
   `:broadcast` mode has.

Server-side subscriptions move the interest filter to the **server**, which buys
both: uninterested clients get nothing on the wire, and the server decides +
**authorizes** who receives each topic (nothing sensitive reaches a client that
shouldn't have it).

## Implementation shape

ActionCable already supports the mechanism: dynamic `stream_from("topic:...")`
driven by client `subscribe` / `unsubscribe` actions **is** a per-connection
subscription registry — self-healing, since the client re-subscribes on remount.
What's needed on top:

- a **topic naming** convention, and
- an **authorization** hook (server checks the connection may subscribe to a
  topic before `stream_from`).

## How it unifies the design

- The **presence roster is already a fixed subscription** ("interest = the
  roster"). Generalizing "interest" to arbitrary topics makes the roster one
  built-in topic.
- It **fixes `:nudge`'s herd**: nudge only the clients subscribed to (and
  authorized for) a topic, instead of the whole account re-polling.
- It **complements, not replaces, `useWaldoEvent`**: keep client-side-filter
  fan-out for simple, high-volume, non-sensitive signals; use server-side
  authorized subscription for sparse interest or sensitive data.

Net: a general **authorized pub/sub layer**, with presence-roster and nudge as
special cases of it.
