# Host handover: move the table to another phone

## Problem

A host who busts stays host. Their phone keeps running the `TableHost`, and the app must stay in the
foreground: iOS tears the listener down when the app is suspended, and every guest hangs in
"Reconnecting…". "End table" ends the table for everyone. So a busted host can neither use their phone
nor go home.

## Goal

The host picks a player in the host menu. That player's phone takes over the server, the save file and
the host rights. The old host becomes an ordinary guest and may leave. Nobody else has to do anything.

Not in scope: handing over only the rights, a consent prompt on the target, handover in the lobby,
automatic recovery when the target fails.

## What already exists

- Guests connect to the Bonjour service name, not to an address (`DiscoveredTable.endpoint`,
  `SeatTicket.endpoint`), and every reconnect resolves the name anew. A new device that advertises the
  same table name with the same code picks the guests up without a client change
  (`SessionTests.resumeOnNewPortViaBonjour` proves the reconnect).
- `TableSession.host(_:)` and `TableSession.join(...)` build complete sessions.
- `TableHost.cancelListener()` waits until the port and the Bonjour name are released.
- `MessageChannel.sendAndClose` sends a last message and closes gracefully.

## Flow

A is the old host, B the target, C any other guest.

1. A's host menu sends `transferHost(to: B)` through the normal command path.
2. A's `TableHost` checks that B has a connection it heard from within the last 12 s (clients ping
   every 5 s). Otherwise it answers `rejected(playerOffline)` and nothing changes. This keeps a suspended
   app from being picked: its TCP connection stays alive, but it sends no pings.
3. `Game` applies the command: `hostID = B`. The command is not an undo step.
4. A's `TableHost` broadcasts the state, acks, and from then on ignores every message. It stops the
   listener and waits until it is gone, sends `handover` (game and tokens) to B, and closes every
   connection without `tableClosed`. It does not report the change to `onChange`, so A's save file stays
   at the state before the transfer.
5. B's session receives `handover`, builds a `HostSnapshot` from it and its own table name and code, and
   starts `TableSession.host`. On success it deletes its seat ticket and publishes the new session as
   `successor`. If hosting cannot start, B shows the `.listen` problem and reconnects as a guest.
6. A's session loses its loopback connection, sees that its `TableHost` has handed the table over, and
   publishes a guest session on the Bonjour endpoint with A's own token as `successor`. When that session
   gets its first `welcome` from B, it deletes A's host save.
7. C's client loses the connection, retries the service name and lands on B.
8. The app shows `session.successor` as soon as one appears.

Both successors start with the predecessor's last state, so the table stays on screen during the gap.

## Rules

- Allowed in every phase except `lobby` and `finished`.
- The menu offers every seated player who is not eliminated and not the host.
- No consent prompt on B. The players sit at one table; B only needs the app open.
- `undo` never changes `hostID`. The new host cannot undo the host rights back to a phone that no longer
  serves.
- The handover carries the 50 newest undo steps. A long tournament's full history exceeds the 1 MiB
  message limit.
- A handover replaces a saved game B may still have in its host save.
- Protocol version 3: the command `transferHost`, the server message `handover`, the rejection
  `playerOffline`.

## Failure handling

- **B is offline or suspended:** `playerOffline`, the table keeps running on A.
- **B cannot start hosting:** B stays a guest and shows the problem. A is not told.
- **B never takes over** (crash, a client that cannot host): A's successor stays in "Reconnecting…" and
  A's host save is still the state before the transfer. A taps "Leave table" and then "Resume game";
  everyone reconnects to A. This is manual on purpose: it reuses the existing resume path.
- **Known gap:** if B starts hosting after A has resumed, Bonjour renames B's service and B hosts alone.
  B has to end that table and has lost its seat. The 12 s liveness check makes this unlikely.

## Security

The target receives everything the host holds: every card, the deck and every reconnect token. That is
the trust the host already has; the handover moves it to a player the host chose.

## Testing

Unit tests in all three packages (command rules, wire format, host behaviour, session swap over Bonjour
on one machine). Manual checks on an iPhone with two simulators: handover mid-hand, old host leaves,
target app in the background, target killed right after the handover.
