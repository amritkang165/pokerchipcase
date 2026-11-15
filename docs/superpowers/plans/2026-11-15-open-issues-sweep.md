# Open Issues Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every open issue that can be fixed and checked with two real iPhones plus simulators: #99, #93, #97, #95, #96, #71, #42, #98, #35, #83, #85, #90.

**Architecture:** Five PRs. A: a guest may remove their own seat in the lobby, so leaving frees it. B: `TableClient` gets a backed-off connect timeout and an app-level `ping`/`pong` heartbeat; `TableHost.start` is serialized. C: configurable debug bots and a debug long game to measure save times. D: the table theme on every screen. E: doc comments and a CI guard.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, Network.framework, DocC, GitHub Actions.

**Spec:** The issue bodies are the spec: `gh issue view <N>`. Design decisions the issues leave open are fixed in each task below.

## Global Constraints

- Swift 6 language mode; fix concurrency errors, do not silence them.
- Code, comments, docs, commits, issue comments in English.
- Conventional Commits with scope: `fix(core): …`, `feat(net): …`, `feat(app): …`, `docs: …`, `ci: …`.
- Each commit body ends with `Closes #N` (`Refs #N` when only part of it).
- Any wire change updates `Sources/PokerNet/PokerNet.docc/Protocol.md` in the same PR. `Wire.version` stays `1`.
- A new public declaration gets its `///` summary in the task that adds it.
- The four CI commands in `AGENTS.md` pass before each PR.
- This plan is committed first, as the first commit of PR A's branch: `docs: plan for the open issues sweep`.
- Line numbers are as of `80fd5d7`; earlier tasks of this plan shift them.
- Merge chains: A → B → E have test coverage and get `gh pr merge --auto --merge` on open. C → D are app-only and wait for the user's check. A branch starts from `origin/main` once its predecessor in the same chain is merged. C and D do not block E; D waits for C because both edit `LobbyView.swift` and `StartView.swift`.
- Each task names its implementer and reviewer (model, effort). Before a PR is opened, the whole branch gets one review: opus high.
- Manual checks are the user's, on two real iPhones; the iPhone SE (3rd gen) simulator is the second device or the small-screen check. The agent copies them into the PR body as an unticked checklist and never ticks them. For A and B they do not hold the merge back.

## Out of scope

- #19 (TLS-PSK on Android): needs an Android device. Stays open.
- #42 last bullet (fixed 200 ms sleep in `messagesAfterRejectionAreIgnored`): closed without code after PR B. The ignored `hello` runs on the rejected connection's own task, and no observer outside it exists without test-only bookkeeping in `TableHost`. The sleep can only let the test pass vacuously, never fail falsely. The other four bullets are done (see the close step in PR B).
- Retrying a lobby leave that the host rejects as `staleState` (Task 1): marked with a `ponytail:` comment.
- Shrinking the save file or saving incrementally (Task 7): becomes a new issue with the measured numbers.

## Checked before this plan was written

At `80fd5d7`, on macOS, outside the repo:

- `swift test` is green, and the file-name filters used below (`--filter LobbyTests`, `WireTests`, `SessionTests`, `ClientTests`, `HostLobbyTests`) select the right tests.
- Task 5's test fails on unchanged code in 6 of 6 runs with `POSIXErrorCode(rawValue: 48): Address already in use`.
- A throwaway implementation of Tasks 1–5 as described here passed the whole suite, with every test of this plan, three times in a row.
- Task 7's simulation with a fixed winner ends at hand 50 with one player left. With the rotating winner below it reaches hand 201: 8,410 history states, 19.1 MB of JSON, 0.36 s to encode and 0.41 s to decode in a debug build on a Mac.
- Task 9's command works and lists 194 undocumented public symbols after the filter (PokerCore 122, PokerNet 33, PokerSession 39).

## Review Focus

1. A guest locks the phone mid-game for a minute while the host stays up: on unlock, the heartbeat must not count the guest's own suspension as host silence (late-tick reset, Task 4; manual check, no test can suspend the process).
2. A guest taps "Leave table" in the lobby while the host is unreachable. Known to be disconnected: leaving ends at once and deletes the ticket (Task 1 test `guestLeavingWhileDisconnectedStillLeaves`). Still shown as connected to a silent host: leaving ends after 2 s, not after the 10 s `ackTimeout` (the `giveUp` task in Task 1 Step 6; no session test can make a real host silent, so the reviewer reads that path).
3. A new guest app at an older host that does not know `ping`: the host answers `malformed` with the ping's id, and the guest stays connected (Task 4 test `olderHostAnsweringMalformedKeepsTheConnection`).
4. The host app comes back from the background twice in quick succession: both `ensureListening` calls succeed on the old port (Task 5 test `concurrentStartsOnTheSamePortBothSucceed`).
5. The connect timeout in both directions. A slow AWDL handshake that needs more than 10 s gets through on the second attempt, which waits 20 s (Task 3 test `connectTimeoutBacksOff`; manual check on two iPhones without shared Wi-Fi). After a long outage the wait is at its 60 s cap, so a hanging attempt is retried up to a minute after the host is back (manual check in PR B; lower `maxConnectTimeout` if that hurts).

---

## PR A: `fix/session-lobby-leave`

### Task 1: A guest leaving in the lobby frees their seat (#99)

Implementer: opus high (core, net, session, protocol). Reviewer: opus high.

**Files:**

- Modify: `Sources/PokerCore/Game.swift:55-63` (`removePlayer` rule)
- Modify: `Sources/PokerSession/TableSession.swift:144-152` (`leave()`)
- Modify: `Sources/PokerNet/PokerNet.docc/Protocol.md:67` (`removePlayer` row)
- Test: `Tests/PokerCoreTests/LobbyTests.swift` (after `removePlayerInLobby`), `Tests/PokerSessionTests/SessionTests.swift` (after `leaveDeletesSaveFiles`)

**Interfaces:**

- Consumes: `TableClient.send(_:) async throws -> AckResult`, `TableClient.disconnect()`, `TableSession.state`, `TableSession.me`.
- Produces: rule change only. `.removePlayer(player: p)` by actor `p` is allowed when `phase == .lobby`; every other non-host actor still gets `.notHost`. No new API.

Why it works: `TableHost.handle` already calls `forget(removed)` for `removePlayer`. That deletes the guest's token and closes the guest's connection with `removed` before any `ack` is sent. `TableClient` then fails the pending send with `ClientError.connectionLost`, which `leave()` ignores. `leave()` cancels `eventTask` before sending, so the guest never shows the "You were removed" alert. An older host rejects the command with `notHost`; the seat then stays, as today.

- [ ] **Step 1: Write the failing core tests**

```swift
@Test func guestMayRemoveOnlyTheirOwnSeatInTheLobby() throws {
    var g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    try g.apply(.join(player: "B", name: "Ben"), by: "A", at: t0)
    try g.apply(.join(player: "C", name: "Cem"), by: "A", at: t0)
    #expect(throws: Rejection.notHost) { try g.apply(.removePlayer(player: "C"), by: "B", at: t0) }
    try g.apply(.removePlayer(player: "B"), by: "B", at: t0)
    #expect(g.state.seats.map(\.id) == ["A", "C"])
}

@Test func guestCannotRemoveTheirOwnSeatOnceStarted() throws {
    var g = Game(hostID: "A", hostName: "Anna", config: .relaxed)
    try g.apply(.join(player: "B", name: "Ben"), by: "A", at: t0)
    try g.apply(.startTournament(button: "A"), by: "A", at: t0)
    #expect(throws: Rejection.notHost) { try g.apply(.removePlayer(player: "B"), by: "B", at: t0) }
}
```

- [ ] **Step 2: Run them**

Run: `swift test --filter LobbyTests`
Expected: `guestMayRemoveOnlyTheirOwnSeatInTheLobby` fails with `notHost` on the self-removal. `guestCannotRemoveTheirOwnSeatOnceStarted` passes already; it pins the rule that stays.

- [ ] **Step 3: Change the guard in `GameState.apply` `.removePlayer` to `guard actor == hostID || (phase == .lobby && actor == player) else { throw .notHost }`**

- [ ] **Step 4: Write the session tests**

```swift
@Test func guestLeavingTheLobbyFreesTheSeat() async throws {
    let anna = try await hostSession()
    defer { Task { await anna.leave() } }
    let ben = await guestSession(anna)
    // Ben's own state too: without it Ben does not know the table is in the lobby and sends nothing.
    try await eventually { anna.state?.seats.count == 2 && ben.state?.seats.count == 2 }
    #expect(await ben.leave())
    try await eventually { anna.state?.seats.count == 1 }
    #expect(await anna.tableHost!.snapshot.tokens.count == 1)
}

@Test func guestLeavingMidTournamentKeepsTheSeat() async throws {
    let anna = try await hostSession()
    defer { Task { await anna.leave() } }
    let ben = await guestSession(anna)
    try await eventually { anna.state?.seats.count == 2 && ben.state?.seats.count == 2 }
    await anna.send(.startTournament(button: anna.me!))
    try await eventually { ben.state?.phase == .betting }
    #expect(await ben.leave())
    try await eventually { await anna.tableHost!.connectedPlayers.count == 1 }
    #expect(anna.state?.seats.count == 2)
}

@Test func guestLeavingWhileDisconnectedStillLeaves() async throws {
    let anna = try await hostSession()
    let tickets: SaveFile<SeatTicket> = tempFile()
    let ben = await guestSession(anna, ticketFile: tickets)
    try await eventually { ben.state?.seats.count == 2 && tickets.load() != nil }
    await anna.tableHost!.stop()
    try await eventually { ben.connection == .reconnecting }
    #expect(await ben.leave())
    #expect(tickets.load() == nil)
    await anna.leave()
}
```

- [ ] **Step 5: Run them**

Run: `swift test --filter SessionTests`
Expected: `guestLeavingTheLobbyFreesTheSeat` times out. The other two pass already; they pin behavior that stays.

- [ ] **Step 6: In `leave()`, between `saveTask?.cancel()` and `await client.disconnect()`, give up the seat**

```swift
if !isHost, state?.phase == .lobby, let me {
    // A silent host must not hold the leave back for the whole ackTimeout: disconnecting fails the send.
    let giveUp = Task { [client] in
        try await Task.sleep(for: .seconds(2))
        await client.disconnect()
    }
    // ponytail: one attempt. A change racing the leave rejects it as staleState and the seat stays
    // until the host removes it; retry once on that rejection if it shows.
    _ = try? await client.send(.removePlayer(player: me))
    giveUp.cancel()
}
```

Update the `leave()` doc comment: "Disconnects; a guest in the lobby gives up their seat first, the host also ends the table for everyone."

- [ ] **Step 7: Run `swift test`, expect all to pass**

- [ ] **Step 8: Update the `removePlayer` row in `Protocol.md`**

Who may send it: "host, not for itself; in the lobby also a guest for their own seat (to leave the table). The host answers a guest's own removal with the `removed` error instead of an `ack` and closes the connection."

- [ ] **Step 9: Commit**

```bash
git add Sources/PokerCore/Game.swift Sources/PokerSession/TableSession.swift Sources/PokerNet/PokerNet.docc/Protocol.md Tests/PokerCoreTests/LobbyTests.swift Tests/PokerSessionTests/SessionTests.swift
git commit -m "fix(session): free the seat when a guest leaves the lobby"   # body: Closes #99
```

**Manual check (user, two iPhones):** host creates a table, guest joins, guest taps "Leave table": the guest's name disappears on the host within a second, and no "You were removed" alert shows on the guest. Repeat after "Start tournament": the seat stays.

### Task 2: Send guard follow-ups (#93)

Implementer: sonnet medium. Reviewer: sonnet medium.

The first bullet of #93 (lobby flicker) shipped in #92. Two remain.

**Files:**

- Modify: `Sources/PokerSession/TableSession.swift:29` (`rejectedAt` doc comment), `:190-192` (`handle` `.state`)
- Test: `Tests/PokerSessionTests/SessionTests.swift:50-56` (`rejectionSurvivesStateWithSameVersion`)

**Interfaces:**

- Produces: `private(set) var stateEvents = 0` in `TableSession` (internal, read by `@testable` tests), incremented once per handled `.state` event. Doc comment: "Number of `state` events handled; lets tests wait for one that changes nothing."

- [ ] **Step 1: In the test, read `let seen = ben.stateEvents` right before `disconnectAll()`; replace the 200 ms sleep and its comment with `try await eventually { ben.stateEvents > seen }`**
- [ ] **Step 2: Run `swift test --filter SessionTests`, expect a compile failure (`stateEvents` missing)**
- [ ] **Step 3: Add `stateEvents` and count it in `handle(.state)`**
- [ ] **Step 4: Change the `rejectedAt` comment to "`state.version` the host had at or after it rejected the command behind `rejection`."**
- [ ] **Step 5: Run `swift test --filter SessionTests`, expect PASS**
- [ ] **Step 6: Commit** `test(session): wait for the rejoin state instead of sleeping` (body: `Closes #93`)

Open PR A with a link to this plan; it auto-merges once CI is green.

---

## PR B: `feat/net-heartbeat`

### Task 3: Back off the connect timeout and cancel its timer (#95, #97)

Implementer: opus high. Reviewer: opus high.

**Files:**

- Modify: `Sources/PokerNet/TableClient.swift` (`init`, `open`, `connectTimedOut`, `receive` `.welcome`, `dropChannel`)
- Modify: `Sources/PokerNet/PokerNet.docc/Protocol.md:171` (recommendation)
- Test: `Tests/PokerNetTests/ClientTests.swift:321-328` (replace `hangingConnectIsRetried`)

**Interfaces:**

- Produces:
  - `static func backoff(_ base: Duration, failures: Int, cap: Duration) -> Duration` (internal): `min(base * 2^failures, cap)`, with the exponent clamped at 16 so it cannot overflow.
  - `init(…, connectTimeout: Duration = .seconds(10), maxConnectTimeout: Duration = .seconds(60))`. Extend the init's doc comment.
  - `private(set) var connectTimeouts = 0` (internal): attempts in a row that the connect timeout dropped. `connectTimedOut` increments it, `welcome` resets it to 0. An attempt that fails fast (refused, reset) does not count: only a timeout says that more time could help.
  - `private var connectTimer: Task<Void, Never>?`: the sleeper from `open()`. It sleeps `backoff(connectTimeout, failures: connectTimeouts, cap: maxConnectTimeout)`. Cancelled in `dropChannel()` and on `welcome`; a cancelled sleeper returns without calling the actor.
- Constraint: `connectTimedOut` sets `connectTimer = nil` before it calls `reconnect()`. Otherwise `dropChannel()` cancels the very task that runs `reconnect()`, and its `retryDelay` sleep returns at once.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func connectTimeoutBacksOff() {
    let waits = (0...4).map { TableClient.backoff(.seconds(10), failures: $0, cap: .seconds(60)) }
    #expect(waits == [.seconds(10), .seconds(20), .seconds(40), .seconds(60), .seconds(60)])
    #expect(TableClient.backoff(.seconds(10), failures: .max, cap: .seconds(60)) == .seconds(60))
}

@Test func hangingConnectIsRetriedUntilTheHostAnswers() async throws {
    let silent = try SilentListener()
    let port = try await silent.start()
    let (ben, events) = await client(port, connectTimeout: .milliseconds(300))
    try await eventually { await silent.connections.count >= 2 }
    #expect(await ben.connectTimeouts >= 1)
    await silent.stop()
    // The silent listener lets go of the port asynchronously.
    var host: TableHost?
    for _ in 0..<50 where host == nil {
        host = try? await startHost(port: port).0
        if host == nil { try await Task.sleep(for: .milliseconds(100)) }
    }
    _ = try await events.first(timeout: .seconds(10)) { $0.welcome != nil }
    #expect(await ben.connectTimeouts == 0)
    await ben.disconnect()
    await host?.stop()
}
```

- [ ] **Step 2: Run, expect a compile failure (`backoff`, `connectTimeouts` missing)**

Run: `swift test --filter ClientTests`

- [ ] **Step 3: Implement as in Interfaces**
- [ ] **Step 4: Run `swift test --filter PokerNetTests`, expect PASS**
- [ ] **Step 5: Replace `Protocol.md:171` with:** "If a connection attempt has not reached `welcome` within 10 s, drop it and try again. Double the wait after each attempt that timed out (10, 20, 40 s, at most 60 s) and start again at 10 s after a `welcome`. A Bonjour resolve or TLS handshake can hang without ever reporting an error, and a slow peer-to-peer handshake can need more than 10 s."
- [ ] **Step 6: Commit** `feat(net): back off the connect timeout on repeated retries` (body: `Closes #95`, `Closes #97`)

### Task 4: App-level heartbeat (#96)

Implementer: opus high. Reviewer: opus high.

**Files:**

- Modify: `Sources/PokerCore/Wire.swift` (`ClientMessage`, `ServerMessage`, both `encode`, `decodeClient`, `decodeServer`)
- Modify: `Sources/PokerNet/TableHost.swift:170-175` (`receive`)
- Modify: `Sources/PokerNet/TableClient.swift` (`init`, `handle`, `receive`, `dropChannel`, new heartbeat)
- Modify: `Sources/PokerNet/PokerNet.docc/Protocol.md` (Client → Host, Host → Client, Flow, Recommendations)
- Test: `Tests/PokerCoreTests/WireTests.swift`, `Tests/PokerNetTests/HostLobbyTests.swift`, `Tests/PokerNetTests/ClientTests.swift`

**Interfaces:**

- Consumes: `connectTimer` handling and `dropChannel()` from Task 3.
- Produces:
  - `ClientMessage.ping` and `ServerMessage.pong`, no associated values; wire type `"ping"` / `"pong"`, payload `{}` (encode a private empty `Encodable` struct; decode ignores the payload).
  - `TableHost` answers every `ping`, bound or not, with `pong` whose envelope `id` is the ping's `id`. A `ping` does not replace `hello`: the `helloTimeout` still closes an unbound connection.
  - `TableClient.init(…, pingInterval: Duration = .seconds(5))`.
  - `private var lastHeard: ContinuousClock.Instant`, set in `handle(_:attempt:)` for every received `.message`, before decoding, so a message this client cannot read counts too.
  - `private var pingTimer: Task<Void, Never>?`: the heartbeat loop, started on `welcome` for the current `generation` and cancelled in `dropChannel()`. Every `pingInterval`:
    1. Stop if the connection is no longer this one (`generation` changed or not `connected`).
    2. If the tick came more than `2 * pingInterval` after the previous one (the first: after `welcome`), this app was suspended: set `lastHeard = .now`.
    3. If `.now - lastHeard >= ackTimeout`: set `pingTimer = nil` (same reason as `connectTimer` in Task 3), call `reconnect()` and stop.
    4. Else send a `ping` with a new envelope `id`.
  - `receive` ignores `.pong`; hearing it was the point.
  - Detection time: at most `ackTimeout + pingInterval` (15 s by default).
- Compatibility: an older host decodes `ping` as an unknown type and answers `malformed` with the same id. `TableClient` ignores that error once connected, and any message counts as heard, so the connection stays. An older client never pings and never gets a `pong`.

- [ ] **Step 1: Write the failing tests**

Wire (`WireTests.swift`, uses the file's `id1` and `json`):

```swift
@Test func pingAndPongGoldenJSON() throws {
    #expect(json(try Wire.encode(ClientMessage.ping, id: id1)) == #"{"id":"00000000-0000-0000-0000-000000000001","payload":{},"type":"ping","v":1}"#)
    #expect(json(try Wire.encode(ServerMessage.pong, id: id1)) == #"{"id":"00000000-0000-0000-0000-000000000001","payload":{},"type":"pong","v":1}"#)
}
```

Also add `.ping` to the list in `clientRoundTrip` and `.pong` to the list in `serverRoundTrip`.

Host (`HostLobbyTests.swift`):

```swift
@Test func pingIsAnsweredWithPongEvenBeforeHello() async throws {
    let (host, port) = try await startHost()
    let ben = try await RawClient.connect(port)
    let id = UUID()
    ben.send(.ping, id: id)
    let reply = try await ben.nextEnvelope { $0 == .pong }
    #expect(reply.id == id)
    await host.stop()
}
```

Client (`ClientTests.swift`; add `pingInterval: Duration = .seconds(5)` to the private `client(…)` helper and pass it on). All three use the same timing, so the two "keeps the connection" tests run three deadlines long:

```swift
@Test func silentHostIsDetectedWhileConnected() async throws {
    let fake = try FakeHost()  // welcomes, never answers ping
    let (ben, events) = await client(try await fake.start(), ackTimeout: .milliseconds(500), pingInterval: .milliseconds(100))
    _ = try await events.first { $0.welcome != nil }
    _ = try await events.first { $0 == .connectionLost }
    try await eventually { await fake.hellos == 2 }
    await ben.disconnect()
    await fake.dropAll()
}

@Test func answeredPingsKeepTheConnection() async throws {
    let (host, port) = try await startHost()
    let (ben, events) = await client(port, ackTimeout: .milliseconds(500), pingInterval: .milliseconds(100))
    _ = try await events.first { $0.welcome != nil }
    try await Task.sleep(for: .milliseconds(1500))
    #expect(!(await events.all.contains(.connectionLost)))
    await ben.disconnect()
    await host.stop()
}

@Test func olderHostAnsweringMalformedKeepsTheConnection() async throws {
    let fake = try FakeHost { id, message in
        guard message == .ping else { return ([], false) }
        return ([try Wire.encode(ServerMessage.error(WireErrorCode.malformed.rawValue), id: id)], false)
    }
    let (ben, events) = await client(try await fake.start(), ackTimeout: .milliseconds(500), pingInterval: .milliseconds(100))
    _ = try await events.first { $0.welcome != nil }
    try await Task.sleep(for: .milliseconds(1500))
    #expect(!(await events.all.contains(.connectionLost)))
    await ben.disconnect()
    await fake.dropAll()
}
```

- [ ] **Step 2: Run `swift test`, expect compile failures (`.ping`, `.pong`, `pingInterval` missing)**
- [ ] **Step 3: Implement the wire cases, the host answer and the client heartbeat as in Interfaces**

Mark the late-tick reset with a `ponytail:` comment: a pong still unread when this app wakes can lose the race against the first tick and drop a healthy connection once; ceiling is one "Reconnecting…" flash, upgrade path is resetting `lastHeard` from `TableSession.appBecameActive`.

- [ ] **Step 4: Run `swift test`, expect PASS**
- [ ] **Step 5: Update `Protocol.md`**
  - Client → Host: new heading "`ping` – heartbeat" with the golden JSON. "Send it every 5 s after `welcome`. The host answers every `ping` with `pong`, also before `hello`; it does not replace `hello`."
  - Host → Client: new heading "`pong` – heartbeat answer" with the golden JSON: "envelope `id` equals the `ping`'s `id`."
  - Flow: add `ping` / `pong`.
  - Recommendations: "If nothing at all (any message type) arrives for 10 s while connected, drop the connection and reconnect with the token. TCP keepalive alone misses a host app that is suspended while its TCP stack still answers. An older host answers `ping` with `malformed`; that counts as an answer. Do not count time your own app was suspended."
- [ ] **Step 6: Commit** `feat(net): detect a silent host with an app-level heartbeat` (body: `Closes #96`)

### Task 5: Serialize `TableHost.start` (#71)

Implementer: opus high. Reviewer: opus high.

**Files:**

- Modify: `Sources/PokerNet/TableHost.swift:37-65`
- Test: `Tests/PokerNetTests/HostLobbyTests.swift`

**Interfaces:**

- Produces: `start(port:)` keeps its signature and doc comment. Its current body moves to `private func bind(port: NWEndpoint.Port) async throws -> NWEndpoint.Port`. `start` chains through `private var lastStart: Task<NWEndpoint.Port, Error>?`: the new task first awaits the previous one's `result` (ignoring its outcome), then calls `bind`; `start` stores the task and returns `try await task.value`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func concurrentStartsOnTheSamePortBothSucceed() async throws {
    let (host, port) = try await startHost()
    async let a = host.start(port: port)
    async let b = host.start(port: port)
    #expect(try await [a, b] == [port, port])
    #expect(await host.isListening)
    await host.stop()
}
```

- [ ] **Step 2: Run `swift test --filter HostLobbyTests`, expect FAIL with `POSIXErrorCode(rawValue: 48): Address already in use`**
- [ ] **Step 3: Implement as in Interfaces**
- [ ] **Step 4: Run `swift test`, expect PASS**
- [ ] **Step 5: Commit** `fix(net): serialize TableHost.start so restarts cannot race for the port` (body: `Closes #71`)

Open PR B with a link to this plan; it auto-merges once CI is green.

- [ ] **Close #42 once PR B is merged.** Its last comment says three bullets are open; the code says one:

```bash
gh issue close 42 --reason "not planned" --comment "Four of five bullets are done: \`start(port:)\` waits for the old listener (\`cancelListener()\`, #70) and is serialized (#71); \`accept\` checks \`listenerID\` (#70); \`eventsFinishWhenTheClientIsReleased\` and the untouched-save assertion in \`snapshotWithoutHostTokenThrows\` exist (#87). The 200 ms sleep in \`messagesAfterRejectionAreIgnored\` stays: the ignored hello runs on the rejected connection's own task, and nothing outside it can observe it without test-only bookkeeping in \`TableHost\`. The sleep can let the test pass vacuously, never fail falsely."
```

**Manual check (user, two iPhones):**

- Guest at the table, idle. Host presses the home button and waits 30 s: the guest shows "Reconnecting…" within 15 s. Host returns: the guest is connected again.
- Host stays away for 3 minutes, then returns: note how long the guest needs to reconnect. More than a minute is a finding for `maxConnectTimeout`.
- Guest locks the phone for 1 min with the host app in front: on unlock the table is live (one "Reconnecting…" flash at most).
- Play 5 minutes: no "Reconnecting…".

---

## PR C: `feat/app-debug-tools`

### Task 6: Configurable debug bots (#98)

Implementer: sonnet medium. Reviewer: sonnet medium.

**Files:**

- Modify: `App/Sources/DebugBots.swift`
- Modify: `App/Sources/LobbyView.swift:71-74`

**Interfaces:**

- Produces (all `#if DEBUG`):
  - `enum BotSpeed: String, CaseIterable { case slow, fast }`, labels "🐢 Slow" and "🐇 Fast", `var delay: Duration` (5 s and 0.8 s, today's value).
  - `enum BotStyle: String, CaseIterable { case call, raise }`, labels "Call" and "Raise".
  - `static func fill(_ host: TableSession, count: Int, speed: BotSpeed = .fast, style: BotStyle = .call)`: joins `min(count, maxSeats - seats)` bots, named from `names` minus names already seated. It replaces `fill(_:seated:)`.
  - `static func action(_ legal: LegalActions, style: BotStyle) -> Action`: `.call` style: `canCheck ? .check : .call`. `.raise` style: `legal.minRaiseTo.map { .raiseTo(amount: $0) }` (already capped at all-in when short), else as `.call`.
  - The bot loop looks every 200 ms. When it sees its turn, it sleeps `speed.delay` and then acts if it is still its turn and `!bot.isSending`. So a slow bot gives at least 5 s on its turn; today's loop acts anywhere between 0 and 0.8 s.
  - `autoStart` calls `fill(host, count: maxSeats)` with the defaults, so `-debugTable` keeps its behavior.
- Lobby: a `Section("Debug bots")` replaces the bare button: `Stepper` "Bots: n" over `1...max(1, free seats)`, segmented `Picker` for speed, segmented `Picker` for style, `Button("Add bots")` disabled at a full table. Values in `@AppStorage("debugBotCount")` (default 9), `("debugBotSpeed")` (default `.fast`), `("debugBotStyle")` (default `.call`).

- [ ] **Step 1: Implement as in Interfaces**
- [ ] **Step 2: Run the app build from `AGENTS.md`, expect success; run `swift test`, expect PASS**
- [ ] **Step 3: Commit** `feat(app): configurable debug bots` (body: `Closes #98`)

**Manual check (user, simulator):** add 2 slow raising bots and start: each raises the minimum after about 5 s, enough to open the host menu and "Fold for" a bot. In a new lobby add 2 slow bots, then 3 fast calling bots on top: 6 seats, no duplicate names. `-debugTable` still fills and starts a full table.

### Task 7: Measure save time in a long tournament (#35)

Implementer: sonnet medium (two app files). Reviewer: sonnet medium. Step 5, if it runs: opus high (persistence), reviewer sonnet medium.

The save cost is `SaveFile.save` (encode and write) and `SaveFile.load` (read and decode) of the whole `HostSnapshot`. `TableSession.host` runs one `load` and one `save` on the main actor; every change runs one `save` on the host actor, inside `TableHost.handle` before `broadcastState()`, so it also delays the state for every player. Timing these two calls once on the device gives all numbers. No library code is instrumented.

**Files:**

- Modify: `App/Sources/DebugBots.swift`, `App/Sources/StartView.swift:63-65`
- Step 5 only: `Sources/PokerSession/TableSession.swift:70-76` (`host`), `App/Sources/StartView.swift:101-104` (`reload`)

**Interfaces:**

- Produces (`#if DEBUG`, in `DebugBots`):
  - `static let long = ProcessInfo.processInfo.arguments.contains("-debugLongGame")`.
  - `static func longGame(hands: Int, hostName: String, tableName: String) throws -> HostSnapshot`: a `.newTable(…, config: .relaxed)` with 9 joined players (names from `names`, new UUID strings as IDs), started with the host as button, then played until `handNumber > hands` or `phase == .finished`. Worst case on purpose, every hand goes to showdown with ten players: betting → the player to act checks if `canCheck`, else calls (actor = that player); showdown → `.resolveShowdown` by the host with `state.pots.map { [$0.eligible[state.handNumber % $0.eligible.count]] }`; hand complete → `.startNextHand` by the host. One `Date()` for every command, so the blinds never rise.
  - The winner rotates on purpose. With a fixed winner the other nine are broke after 50 hands and the tournament is finished.
  - `static func reportSaveTimes(_ snapshot: HostSnapshot)`: times one `SaveFile.host.save(snapshot)` and one `SaveFile.host.load()` with `ContinuousClock().measure` and prints one line: history count, file size in bytes, save time, load time.
- `StartView`: next to the `-debugTable` task, `if DebugBots.long, !name.isEmpty`: build `longGame(hands: 200, hostName: name, tableName: defaultTableName)`, call `reportSaveTimes`, then `host(…)` it.

- [ ] **Step 1: Implement as in Interfaces; run the app build and `swift test`, expect success**
- [ ] **Step 2: Commit** `feat(app): debug long game to measure save times` (body: `Refs #35`)
- [ ] **Step 3: The user measures on an iPhone from Xcode with `-debugLongGame -playerName <name>`** and reports the printed line. It is a debug build, so the times are an upper bound. Expect about 8,400 states and 19 MB; a Mac needs 0.36 s to save and 0.41 s to load, so both limits below are likely exceeded.
- [ ] **Step 4: Comment the numbers on #35**
- [ ] **Step 5: Only if `load` + `save` take more than 50 ms: move them off the main actor**

In `TableSession.host`, replace the `load` and first `save` with `let previous = try await Task.detached { let old = saveFile.load(); try saveFile.save(snapshot); return old }.value`. In `StartView.reload`, load both files in one `Task.detached` and assign the results back on the main actor. Run `swift test` (`failedStartRestoresThePreviousSave` and `snapshotWithoutHostTokenThrows` pin the behavior), expect PASS. The user measures again. Commit `perf(session): load and save the host snapshot off the main actor` (body: `Closes #35`).

- [ ] **Step 6: Only if one `save` takes more than 250 ms: open a new issue** labeled `deferred` and `core`, with the numbers. Say in it that `TableHost.handle` saves before it broadcasts, and name the candidates: save after the broadcast and ack, cap the undo history, or save incrementally. That needs a design, not this sweep.
- [ ] **Step 7: If Step 5 did not run, close #35 by hand** with a link to the comment from Step 4 and, if there is one, the new issue.

Open PR C after Step 2 with a link to this plan; it waits for the user's check and for Steps 3–7.

---

## PR D: `feat/app-theme-screens`

### Task 8: Table theme on every screen (#83)

Implementer: opus high (multi-file UI). Reviewer: sonnet medium.

**Files:**

- Modify: `App/Sources/Theme.swift` (two modifiers)
- Modify: `App/Sources/StartView.swift` (`StartView`, `CreateTableSheet`, `JoinSheet`), `SettingsView.swift`, `TableScreen.swift` (stack content, banner), `LobbyView.swift`, `RankingView.swift`, `ShowdownView.swift`

**Interfaces:**

- Produces in `Theme.swift`:
  - `func themedScreen() -> some View`: `scrollContentBackground(.hidden)`, `background(theme.background.ignoresSafeArea())`, `foregroundStyle(theme.text)`, `tint(theme.accent)`, `toolbarBackground(theme.background, for: .navigationBar)`, `toolbarColorScheme(.dark, for: .navigationBar)`, `environment(\.colorScheme, .dark)`. Both themes have dark grounds, so system controls render in their dark style.
  - It does not set the toolbar background's visibility. `TableScreen.swift:39` hides it for the table from outside `TableView`, and a `.visible` further out would win over that.
  - `func themedRow() -> some View`: `listRowBackground(theme.seat)`, applied to each `Section` (or bare row) in lists and forms.
- `themed()` at the app root and `formTint` stay: they pick the theme, and they tint whatever the system still draws in the window's scheme.
- Where: `themedScreen()` is the last modifier inside each `NavigationStack`, after `.navigationTitle`, `.toolbar` and `.safeAreaInset`, so toolbar buttons and the banner get tint and scheme too. That is the `Form` chain in `StartView`, `CreateTableSheet`, `JoinSheet` and `SettingsView`, and the `Group` chain in `TableScreen` (covers lobby, ranking, "Connecting…" and the table). `themedRow()` on every section or row of those lists and on `RankingView`'s rows.
- Replace `.foregroundStyle(.secondary)` with `theme.muted` in `StartView` (2), `LobbyView` (2), `ShowdownView` (3). Error text stays `.red`.
- `RankingView`: "Leave table" uses `ThemeButtonStyle()` instead of `.borderedProminent`.
- `TableScreen` banner: `background(theme.background)` instead of `.bar`.
- No change: `TableView` (its own three toolbar lines at `:48-50` now repeat `themedScreen()`; leave them), `LocalNetworkNotice` (inherits text color and tint), `Messages.swift` (strings only), `HostMenu` (system menu).
- If the navigation title stays dark on Felt, the bar ignores `toolbarColorScheme` while its background is not visible. Then add `.toolbarBackground(.visible, for: .navigationBar)` on the four forms and inside `LobbyView` and `RankingView`, never on the `Group` in `TableScreen`.

- [ ] **Step 1: Take "before" screenshots in the simulator.** Launch arguments set the stored values: `-appearance felt|dark -playerName Du`, and `-debugTable` for a full table. `xcrun simctl io booted screenshot <file>`.
- [ ] **Step 2: Implement as in Interfaces**
- [ ] **Step 3: Run the app build and `pre-commit run --all-files`, expect success**
- [ ] **Step 4: Take the same screenshots again and look at them:** start screen, create and join sheets, settings, lobby, table, ranking, in Felt and Dark. Text, section headers, text fields, stepper and segmented pickers are readable; the navigation bar matches the screen; the table screen has no bar background or hairline. Fix what is not.
- [ ] **Step 5: Commit** `feat(app): apply the table theme to every screen` (body: `Closes #83`)

Open PR D with the before and after screenshots of both themes and a link to this plan; it waits for the user's check.

**Manual check (user, iPhone and SE3 simulator, Felt and Dark):** the screens from Step 4, plus lobby as guest, "Connecting…", showdown and a red banner (reject a command). The host menu, alerts and confirmation dialogs are system-drawn: a readable tint is enough.

---

## PR E: `chore/docs-ci`

Starts once PR B is merged, so it covers the API that A and B add.

### Task 9: Doc comments for the remaining public API (#85)

Implementer: sonnet medium. Reviewer: sonnet medium.

**Files:** public declarations in `Sources/PokerCore`, `Sources/PokerNet`, `Sources/PokerSession` that the list from Step 1 names. 194 at `80fd5d7`: 122, 33 and 39.

- [ ] **Step 1: List the undocumented symbols**

```bash
xcodebuild docbuild -scheme PokerChipCase-Package -destination 'generic/platform=macOS' -derivedDataPath .build/docs OTHER_DOCC_FLAGS=--experimental-documentation-coverage -quiet
jq -r '.[] | select(.kind.isSymbol and (.hasAbstract | not)) | .referencePath
  | sub("^doc://[^/]+/documentation/"; "")
  | select(test("/(==|!=)\\(_:_:\\)$|/init\\(from:\\)$|/encode\\(to:\\)$|/hash\\(into:\\)$|/hashValue$|/localizedDescription$|/init\\(rawValue:\\)$|/rawValue$|/allCases$|Isolated\\(|/withSerialExecutor|^PokerSession/Poker(Core|Net)(/[^/]+)?$") | not)' \
  .build/docs/Build/Products/Debug/*.doccarchive/documentation-coverage.json | sort
```

The filter drops what no source line can document: synthesized `Equatable`, `Codable`, `Hashable`, `RawRepresentable`, `CaseIterable` and `Error` members, the actor defaults, and the pages DocC makes for extended modules.

- [ ] **Step 2: Add a one-line `///` summary to each listed symbol, enum cases included; no comments on non-public code.** Say what the reader cannot see in the name: the unit, when it is nil, who may call it.
- [ ] **Step 3: Re-run Step 1, expect no output; run the docs command from `AGENTS.md` (warnings as errors), expect success**
- [ ] **Step 4: Commit** `docs: doc comments for the remaining public API` (body: `Closes #85`)

### Task 10: Skip the SonarCloud issue check when the scan did not run (#90)

Implementer: haiku medium. Reviewer: sonnet medium.

**Files:** `.github/workflows/ci.yml:60-68`

- [ ] **Step 1: Give the "SonarCloud scan" step `id: sonar`; change the issue check's condition to `if: ${{ !cancelled() && env.HAS_SONAR_TOKEN == 'true' && steps.sonar.conclusion != 'skipped' }}`**

Not `== 'success'`: `sonar.qualitygate.wait=true` fails the scan step on a red quality gate, and that is when the annotations are wanted.

- [ ] **Step 2: Run `pre-commit run --all-files` (actionlint, zizmor), expect PASS**
- [ ] **Step 3: Commit** `ci: skip the SonarCloud issue check when the scan did not run` (body: `Closes #90`)

Open PR E with a link to this plan; it auto-merges once CI is green. Its own CI run shows the check still runs after a scan; the skipped path shows the next time `swift test` fails on a PR.
