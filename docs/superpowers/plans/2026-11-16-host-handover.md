# Host Handover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The host can move the table (server, save file, host rights) to another player's phone and then leave.

**Architecture:** A new command `transferHost` changes `hostID` in the game. The old `TableHost` then stops listening, sends its game and tokens to the target in a new `handover` message and closes every connection. The target's `TableSession` starts a new `TableHost` under the same Bonjour name; the old host's session becomes a guest. Both publish the replacement session as `successor`, and the app swaps to it. Guests reconnect by service name without any change.

**Tech Stack:** Swift 6 (language mode 6), Network.framework, Swift Testing, SwiftUI, DocC.

**Spec:** `docs/superpowers/specs/2026-11-16-host-handover-design.md`

## Global Constraints

- Swift 6 language mode stays. Fix concurrency errors, do not silence them.
- Code, comments, docs and commits in English. Commits follow Conventional Commits with an optional scope.
- Every new `public` symbol gets a doc comment: the DocC build runs with `--warnings-as-errors`.
- No new dependencies.
- Wire protocol version is `3`. `Sources/PokerNet/PokerNet.docc/Protocol.md` changes in the same PR.
- Liveness window for a handover target: `12` seconds. Undo steps a handover carries: `50`.
- Handover is refused in `lobby` and `finished`.
- A deliberate shortcut gets a `ponytail:` comment naming its ceiling and upgrade path.
- Each task ends with `swift test` green for the whole package, not only its own filter.

## Review Focus

Each line is pinned by the test named after it.

1. The target's app is suspended: its connection is alive but silent. Expected: `playerOffline`, the table keeps running. Test: `silentTargetIsRejectedUntilItPings` (Task 3).
2. The target never takes over (crash, a client that cannot host). Expected: the old host still has its save from before the transfer and can resume. Test: `oldHostKeepsItsSaveUntilTheNewHostAnswers` (Task 4).
3. Long tournament with ten players and digital cards. Expected: the `handover` message stays below the 1 MiB line limit. Test: `handoverWithFiftyUndoStepsFitsOneMessage` (Task 2).
4. The new host taps Undo right after the handover. Expected: the game steps back, the host rights stay. Test: `transferHostIsNotAnUndoStepAndSurvivesUndo` (Task 1).
5. The target cannot start hosting (its save file cannot be written). Expected: it stays a guest, shows the problem and keeps reconnecting. Test: `failedTakeoverIsShownAndTheGuestStaysAGuest` (Task 4).

## File Structure

| File | Change |
|---|---|
| `Sources/PokerCore/Command.swift` | `Command.transferHost`, `Rejection.playerOffline` |
| `Sources/PokerCore/Game.swift` | rule for `transferHost`, undo keeps `hostID`, `keepHistory(last:)` |
| `Sources/PokerCore/Wire.swift` | `Handover`, `ServerMessage.handover`, version 3 |
| `Sources/PokerNet/TableClient.swift` | `ClientEvent.handover` |
| `Sources/PokerNet/HostSnapshot.swift` | public memberwise `init` |
| `Sources/PokerNet/TableHost.swift` | liveness, handover, `handedOver` |
| `Sources/PokerNet/PokerNet.docc/Protocol.md` | version 3 |
| `Sources/PokerSession/TableSession.swift` | `successor`, take over, step down |
| `App/Sources/Messages.swift`, `HostMenu.swift`, `TableScreen.swift`, `PokerChipCaseApp.swift` | text, menu, session swap |
| `Tests/PokerCoreTests/TransferHostTests.swift` (new), `WireTests.swift` | core tests |
| `Tests/PokerNetTests/HostHandoverTests.swift` (new), `Helpers.swift`, `HostCommandTests.swift` | host tests |
| `Tests/PokerSessionTests/HandoverTests.swift` (new), `Helpers.swift` | session tests |

---

### Task 1: Core command `transferHost`

**Files:**

- Modify: `Sources/PokerCore/Command.swift`, `Sources/PokerCore/Game.swift`, `App/Sources/Messages.swift`
- Test: `Tests/PokerCoreTests/TransferHostTests.swift` (create)

**Interfaces:**

- Produces: `Command.transferHost(to: PlayerID)` (JSON `{"transferHost":{"to":"B"}}`), `Rejection.playerOffline`, `public mutating func keepHistory(last count: Int)` on `Game`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import PokerCore

@Test func transferHostMovesTheHostRights() throws {
    var g = try Game.started()
    let version = g.state.version
    try g.apply(.transferHost(to: "B"), by: "A", at: t0)
    #expect(g.state.hostID == "B" && g.state.version == version + 1)
    #expect(throws: Rejection.notHost) { try g.apply(.pauseClock, by: "A", at: t0) }
    try g.apply(.pauseClock, by: "B", at: t0)
    try g.apply(.removePlayer(player: "A"), by: "B", at: t0)
}

@Test func transferHostGuards() throws {
    var g = try Game.started()
    #expect(throws: Rejection.notHost) { try g.apply(.transferHost(to: "C"), by: "B", at: t0) }
    #expect(throws: Rejection.unknownPlayer) { try g.apply(.transferHost(to: "X"), by: "A", at: t0) }
    #expect(throws: Rejection.illegalAction) { try g.apply(.transferHost(to: "A"), by: "A", at: t0) }
    g.state.phase = .finished
    #expect(throws: Rejection.invalidPhase) { try g.apply(.transferHost(to: "B"), by: "A", at: t0) }
    var lobby = Game(hostID: "A", hostName: "A", config: TournamentConfig(startingStack: 1000, levels: tenTwenty))
    try lobby.apply(.join(player: "B", name: "B"), by: "A", at: t0)
    #expect(throws: Rejection.invalidPhase) { try lobby.apply(.transferHost(to: "B"), by: "A", at: t0) }
    #expect(g.state.hostID == "A" && lobby.state.hostID == "A")
}

@Test func transferHostIsNotAnUndoStepAndSurvivesUndo() throws {
    var g = try Game.started()
    try g.act(.fold)  // A folds; B is next
    let steps = g.history.count
    try g.apply(.transferHost(to: "B"), by: "A", at: t0)
    #expect(g.history.count == steps)
    try g.apply(.undo, by: "B", at: t0)
    #expect(g.state.hostID == "B" && g.toAct == "A")
}

@Test func keepHistoryDropsTheOldestSteps() throws {
    var g = try Game.started()
    try g.act(.call)
    try g.act(.call)
    let newest = g.history.last
    g.keepHistory(last: 1)
    #expect(g.history.count == 1 && g.history.last == newest)
    g.keepHistory(last: 5)
    #expect(g.history.count == 1)
}
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'transferHost|keepHistory'`
Expected: build error, `type 'Command' has no member 'transferHost'`.

- [ ] **Step 3: Add the cases in `Command.swift`**

`case transferHost(to: PlayerID)` in `Command`, doc comment: "Makes another seated player the host; host only, not in the lobby and not after the tournament finished. The host device then hands the table over, see the PokerNet protocol article."

`case playerOffline` in `Rejection`, doc comment: "The player a host handover names has no live connection to the host."

- [ ] **Step 4: Implement the rule in `Game.swift`**

In `GameState.apply`, a new `case let .transferHost(player):` with these guards in this order: `actor == hostID` else `.notHost`; `phase != .lobby && phase != .finished` else `.invalidPhase`; `seat(player) != nil` else `.unknownPlayer`; `player != hostID` else `.illegalAction`. Then `hostID = player`.

In `Game.apply`:

- `transferHost` adds no history step, like `pauseClock` and `resumeClock`.
- The undo branch sets `previous.hostID = state.hostID` before `state = previous`, with the comment "The host is not undone: the phone that handed the table over no longer serves it."

New method on `Game`:

```swift
/// Drops all but the `count` newest undo steps.
public mutating func keepHistory(last count: Int)
```

- [ ] **Step 5: Add the rejection text in `App/Sources/Messages.swift`**

`case .playerOffline: "That player's app is not open"` in `Rejection.message`. The switch is exhaustive, so the app does not build without it.

- [ ] **Step 6: Run the tests**

Run: `swift test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/PokerCore/Command.swift Sources/PokerCore/Game.swift App/Sources/Messages.swift Tests/PokerCoreTests/TransferHostTests.swift
git commit -m "feat(core): transferHost command makes another player the host"
```

---

### Task 2: Wire version 3 with the `handover` message

**Files:**

- Modify: `Sources/PokerCore/Wire.swift`, `Sources/PokerCore/PokerCore.docc/PokerCore.md`, `Sources/PokerNet/TableClient.swift`, `Sources/PokerSession/TableSession.swift`, `Sources/PokerNet/PokerNet.docc/Protocol.md`
- Test: `Tests/PokerCoreTests/WireTests.swift`, `Tests/PokerNetTests/HostCommandTests.swift:84`, `Tests/PokerNetTests/Helpers.swift`

**Interfaces:**

- Consumes: `Command.transferHost(to:)`, `Game.keepHistory(last:)` from Task 1.
- Produces:
  - `public struct Handover: Codable, Equatable, Sendable { public var game: Game; public var tokens: [String: PlayerID]; public init(game: Game, tokens: [String: PlayerID]) }` in `Wire.swift`
  - `ServerMessage.handover(Handover)`, envelope type `"handover"`
  - `Wire.version == 3`
  - `ClientEvent.handover(Handover)`, yielded by `TableClient` when the message arrives
  - `extension ServerMessage { var handover: Handover? }` in `Tests/PokerNetTests/Helpers.swift`

- [ ] **Step 1: Update and add the wire tests**

In `WireTests.swift` replace every `"v":2` with `"v":3`, and change `versionMismatchRejected` to send `"v":2` and expect `WireError.versionMismatch(2)`. In `HostCommandTests.swift` line 84 replace `"v":2` with `"v":3`. Add `.handover(Handover(game: g, tokens: ["secret": "B"]))` to the list in `serverRoundTrip`. Add:

```swift
@Test func transferHostGoldenJSON() throws {
    let request = CommandRequest(command: .transferHost(to: "B"), stateVersion: 7)
    #expect(json(try Wire.encode(ClientMessage.command(request), id: id1)) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"command":{"transferHost":{"to":"B"}},"stateVersion":7},"type":"command","v":3}"#)
}

@Test func handoverPayloadHasGameAndTokens() throws {
    let g = try Game.started()
    let data = try Wire.encode(ServerMessage.handover(Handover(game: g, tokens: ["secret": "B"])), id: id1)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let payload = try #require(object["payload"] as? [String: Any])
    let game = try #require(payload["game"] as? [String: Any])
    #expect(object["type"] as? String == "handover")
    #expect(payload["tokens"] as? [String: String] == ["secret": "B"])
    #expect(game["state"] != nil && (game["history"] as? [Any])?.count == g.history.count)
}

/// 1 MiB is `MessageChannel.maxMessageSize`: a longer line makes the receiver drop the connection.
@Test func handoverWithFiftyUndoStepsFitsOneMessage() throws {
    var g = try Game.started(
        ["A": 1000, "B": 1000, "C": 1000, "D": 1000, "E": 1000, "F": 1000, "G": 1000, "H": 1000, "I": 1000, "J": 1000],
        digital: true)
    for _ in 0..<3 {
        try g.checkDown()
        try g.apply(.startNextHand, by: "A", at: t0)
    }
    #expect(g.history.count > 50)
    g.keepHistory(last: 50)
    let data = try Wire.encode(ServerMessage.handover(Handover(game: g, tokens: [:])), id: id1)
    #expect(data.count < 1_048_576)
}
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'GoldenJSON|handover|RoundTrip|Rejected'`
Expected: build error, `cannot find 'Handover' in scope`.

- [ ] **Step 3: Implement in `Wire.swift`**

Add `Handover` (doc comment: "What a guest needs to take the table over: the whole game with its undo steps, hidden cards and deck, and every reconnect token. Sent by a host that hands the table over."), `ServerMessage.handover` (doc comment: "Tells the receiver to host the table from now on; the sender closes every connection right after."), the `"handover"` branches in `Wire.encode` and `Wire.decodeServer`, and `version = 3`. Update the `{"v": 2, …}` in the doc comment of `Wire`. Add ``Handover`` to "Wire types" in `PokerCore.md`.

- [ ] **Step 4: Pass the message through `TableClient`**

`case handover(Handover)` in `ClientEvent` (doc comment: "The host handed the table over to this device; it closes the connection right after."). In `receive`, `case let .handover(handover): continuation.yield(.handover(handover))`.

In `TableSession.handle` add `case .handover: break` so the package builds; Task 4 replaces it. In `Tests/PokerNetTests/Helpers.swift` add `var handover: Handover?` next to the other `ServerMessage` accessors.

Task 3's `tableClientReportsTheHandover` covers this path end to end.

- [ ] **Step 5: Update `Protocol.md`**

- Title: "(version 3)". Every `"v":2` becomes `"v":3`.
- Command table, new row after `removePlayer`: `| transferHost | to (player ID) | host; not in the lobby and not after the tournament finished. See "Host handover". |`
- Reasons list: append `playerOffline`.
- State table: the `hostID` row reads "`hostID` changes when the host hands the table over".
- New section after `pong`:

````markdown
### `handover` – take the table over

```json
{"id":"…","payload":{"game":{"history":[…],"state":{…}},"tokens":{"<token>":"<player ID>"}},"type":"handover","v":3}
```

Sent to exactly one client: the player a `transferHost` named. `game.state` is the unredacted `GameState`, with every seat's `holeCards` and the `deck`. `game.history` holds the newest undo steps (at most 50), oldest first, each a `GameState`. `tokens` maps every reconnect token to its player. The host closes the connection right after this message.
````

- New section before "Versions":

````markdown
## Host handover

The host can move the table to another player's device, for example before leaving.

1. The host device's own client sends `transferHost` with the target's player ID.
2. The host answers `rejected` with `playerOffline` if the target has no connection that sent any message in the last 12 s. This check comes before the other rules. A client that pings every 5 s passes it.
3. Otherwise the host sets `hostID` to the target, broadcasts the `state`, acks, and ignores every later message.
4. The host stops listening and withdraws its Bonjour service, sends `handover` to the target and closes every connection. It sends no `tableClosed`.
5. The target starts listening, advertises the same table name and accepts the same code and tokens.
6. Every other client, the old host included, sees a dropped connection and reconnects to the service name with its token as usual.

`undo` never changes `hostID`. If the target does not take over, the old host can open the table again from its save, which holds the state before the transfer.
````

- "Versions": append "Version 3 added the host handover (`transferHost`, `handover`, `playerOffline`)."
- "Recommendations for clients", two new bullets: "After a dropped connection, resolve the Bonjour service name again instead of reusing the old address: the table may have moved to another device." and "A client that cannot host ignores `handover`. Tell the user, because the table is down until the old host opens it again."
- "Security", one new bullet: "A `handover` gives the target everything the host holds: every card, the deck and every token."

- [ ] **Step 6: Run the tests**

Run: `swift test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/PokerCore Sources/PokerNet/TableClient.swift Sources/PokerNet/PokerNet.docc/Protocol.md Sources/PokerSession/TableSession.swift Tests/PokerCoreTests/WireTests.swift Tests/PokerNetTests/HostCommandTests.swift Tests/PokerNetTests/Helpers.swift
git commit -m "feat(protocol): version 3 with the handover message"
```

---

### Task 3: `TableHost` hands the table over

**Files:**

- Modify: `Sources/PokerNet/TableHost.swift`, `Sources/PokerNet/HostSnapshot.swift`, `Tests/PokerNetTests/Helpers.swift`, `Tests/PokerNetTests/ClientTests.swift`
- Test: `Tests/PokerNetTests/HostHandoverTests.swift` (create)

**Interfaces:**

- Consumes: `Command.transferHost(to:)`, `Rejection.playerOffline`, `Game.keepHistory(last:)`, `Handover`, `ServerMessage.handover`, `ClientEvent.handover`.
- Produces:
  - `TableHost.init(snapshot:helloTimeout:liveWindow:onChange:)` with `liveWindow: Duration = .seconds(12)`
  - `public private(set) var handedOver: Bool` on `TableHost`: true from the moment a `transferHost` was accepted
  - `static let handoverHistory = 50` on `TableHost`
  - `public init(game: Game, tokens: [String: PlayerID], tableName: String, code: TableCode)` on `HostSnapshot`
  - Test helpers: `startHost(_:port:helloTimeout:liveWindow:onChange:)` and `Table.open(snapshot:liveWindow:onChange:)`, both with `liveWindow: Duration = .seconds(12)`

- [ ] **Step 1: Extend the test helpers**

Add the `liveWindow` parameter to `startHost` and `Table.open` in `Tests/PokerNetTests/Helpers.swift` and pass it through to `TableHost.init`. Add `var handover: Handover?` to the `ClientEvent` extension at the top of `Tests/PokerNetTests/ClientTests.swift`.

- [ ] **Step 2: Write the failing tests**

```swift
import Foundation
import Network
import PokerCore
import Testing
@testable import PokerNet

/// Host IDs of every snapshot passed to `onChange`.
private actor SavedHosts {
    var ids: Set<PlayerID> = []
    func add(_ id: PlayerID) { ids.insert(id) }
}

@Suite(.timeLimit(.minutes(1)))
struct HostHandoverTests {
    /// Starts the tournament and returns the version both clients have seen.
    private func start(_ t: Table) async throws -> Int {
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        let version = try await t.anna.state { $0.phase == .betting }.version
        _ = try await t.ben.state { $0.phase == .betting }
        return version
    }

    @Test func handoverGoesToTheTargetAndTheHostStops() async throws {
        let saved = SavedHosts()
        let t = try await Table.open(onChange: { s in Task { await saved.add(s.game.state.hostID) } })
        let version = try await start(t)
        let ben = t.benWelcome.player
        let id = UUID()
        t.anna.send(t.command(.transferHost(to: ben), version: version), id: id)
        #expect(try await t.anna.ack() == Ack(id: id, result: .ok))
        let handover = try #require(try await t.ben.next { $0.handover != nil }.handover)
        #expect(handover.game.state.hostID == ben && handover.game.state.version == version + 1)
        #expect(handover.game.history.count <= TableHost.handoverHistory)
        #expect(handover.tokens.count == 2 && handover.tokens[t.benWelcome.token] == ben)
        try await t.ben.waitForClose()
        try await t.anna.waitForClose()
        #expect(await t.host.handedOver)
        #expect(await !t.host.isListening)
        // No save names the new host, so the old host can resume if the target fails.
        try await Task.sleep(for: .milliseconds(200))
        #expect(await saved.ids == [t.hostID])
    }

    @Test func disconnectedTargetIsRejected() async throws {
        let t = try await Table.open()
        let version = try await start(t)
        t.ben.close()
        try await eventually { await !t.host.connectedPlayers.contains(t.benWelcome.player) }
        t.anna.send(t.command(.transferHost(to: t.benWelcome.player), version: version))
        #expect(try await t.anna.ack().result == .rejected(reason: .playerOffline))
        #expect(await t.host.isListening)
        #expect(await t.host.snapshot.game.state.hostID == t.hostID)
        #expect(await !t.host.handedOver)
        await t.host.stop()
    }

    /// A suspended app keeps its TCP connection but sends nothing.
    @Test func silentTargetIsRejectedUntilItPings() async throws {
        let t = try await Table.open(liveWindow: .milliseconds(500))
        let version = try await start(t)
        try await Task.sleep(for: .milliseconds(700))
        t.anna.send(t.command(.transferHost(to: t.benWelcome.player), version: version))
        #expect(try await t.anna.ack().result == .rejected(reason: .playerOffline))
        t.ben.send(.ping)
        _ = try await t.ben.next { $0 == .pong }
        t.anna.send(t.command(.transferHost(to: t.benWelcome.player), version: version))
        #expect(try await t.anna.ack().result == .ok)
        _ = try await t.ben.next { $0.handover != nil }
    }

    @Test func tableClientReportsTheHandover() async throws {
        let (host, port) = try await startHost()
        let anna = try await RawClient.connect(port)
        anna.send(hello("Anna", token: await host.snapshot.hostToken))
        let hostID = try await anna.welcome().player
        let ben = TableClient(endpoint: loopback(port), code: code4711, name: "Ben")
        let events = EventRecorder(ben.events)
        await ben.connect()
        let welcome = try #require(try await events.first { $0.welcome != nil }.welcome)
        let lobby = try await anna.state { $0.seats.count == 2 }
        anna.send(.command(CommandRequest(command: .startTournament(button: hostID), stateVersion: lobby.version)))
        let version = try await anna.state { $0.phase == .betting }.version
        anna.send(.command(CommandRequest(command: .transferHost(to: welcome.player), stateVersion: version)))
        let handover = try #require(try await events.first { $0.handover != nil }.handover)
        #expect(handover.game.state.hostID == welcome.player)
        await ben.disconnect()
    }
}
```

- [ ] **Step 3: Run them and see them fail**

Run: `swift test --filter HostHandoverTests`
Expected: build error, `extra argument 'liveWindow' in call`.

- [ ] **Step 4: Add the public initializer to `HostSnapshot`**

`public init(game: Game, tokens: [String: PlayerID], tableName: String, code: TableCode)`, doc comment: "Creates a snapshot from its parts, for a device that takes a table over." `newTable` keeps using it.

- [ ] **Step 5: Implement the handover in `TableHost.swift`**

State and parameters:

- `liveWindow: Duration` init parameter (default `.seconds(12)`), documented: "a handover target must have sent a message within this time".
- `private var lastHeard: [UUID: ContinuousClock.Instant]`: set at the top of `receive` for every message of a known connection, cleared in `drop`.
- `public private(set) var handedOver = false`, doc comment: "True once this host accepted a `transferHost`: it has stopped serving and another device hosts the table."
- `static let handoverHistory = 50`, doc comment: "Undo steps a handover carries; the whole history of a long tournament exceeds `MessageChannel.maxMessageSize`."

Behaviour:

- `receive` returns at once while `handedOver` is true.
- In `handle`, before `snapshot.game.apply`: for `.transferHost(to: target)`, find a connection bound to `target` whose `lastHeard` is younger than `liveWindow`. If there is none, ack `.rejected(reason: .playerOffline)` and return.
- After a successful apply of `transferHost`: `broadcastState()`, ack `.ok`, set `handedOver = true` and `port = nil` (so `ensureListening` does nothing), start `Task { await finishHandover(to: connection) }` and return. Do not call `onChange`, `forget` or `forgetRemovedPlayers`.
- `private func finishHandover(to id: UUID) async`, in this order: `await cancelListener()`; copy `snapshot.game`, `keepHistory(last: Self.handoverHistory)`; encode `ServerMessage.handover(Handover(game:tokens:))` with `snapshot.tokens`; `channels[id]?.sendAndClose(data)`; `drop(id)`; `disconnectAll()`.

The order matters: the Bonjour name must be free before the target can register it, and `sendAndClose` must run before `disconnectAll` would cancel the target's channel.

Update the type's doc comment with one sentence on the handover.

- [ ] **Step 6: Run the tests**

Run: `swift test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/PokerNet/TableHost.swift Sources/PokerNet/HostSnapshot.swift Tests/PokerNetTests
git commit -m "feat(net): the host hands the table over to a live player"
```

---

### Task 4: `TableSession` takes over and steps down

**Files:**

- Modify: `Sources/PokerSession/TableSession.swift`, `Tests/PokerSessionTests/Helpers.swift`
- Test: `Tests/PokerSessionTests/HandoverTests.swift` (create)

**Interfaces:**

- Consumes: `ClientEvent.handover(Handover)`, `TableHost.handedOver`, `HostSnapshot.init(game:tokens:tableName:code:)`.
- Produces:
  - `public private(set) var successor: TableSession?` on `TableSession`
  - `TableSession.host(_:saveFile:ticketFile:port:)` with `ticketFile: SaveFile<SeatTicket> = .seat`
  - `TableSession.join(endpoint:tableName:code:name:token:ticketFile:saveFile:)` with `saveFile: SaveFile<HostSnapshot> = .host`
  - Test helpers: `hostSession(_:ticketFile:)` and `guestSession(_:name:token:code:ticketFile:saveFile:)`, the new parameters defaulting to `tempFile()`

- [ ] **Step 1: Extend the test helpers**

In `Tests/PokerSessionTests/Helpers.swift` add `ticketFile: SaveFile<SeatTicket> = tempFile()` to `hostSession` and `saveFile: SaveFile<HostSnapshot> = tempFile()` to `guestSession`, passed through. No test may reach the real files in Application Support.

- [ ] **Step 2: Write the failing tests**

```swift
import Foundation
import Network
import Testing
@testable import PokerCore
@testable import PokerNet
@testable import PokerSession

@MainActor @Suite(.timeLimit(.minutes(2)))
struct HandoverTests {
    /// A name of its own for every test: the old host's guest session looks the table up by name over
    /// Bonjour, and the other suites host tables called "Test" at the same time.
    private func uniqueName() -> String { "T-\(UUID().uuidString.prefix(8))" }

    private func hostUnique(_ save: SaveFile<HostSnapshot> = tempFile()) async throws -> TableSession {
        let anna = try await TableSession.host(
            .newTable(hostName: "Anna", tableName: uniqueName(), code: code4711, config: .relaxed),
            saveFile: save, ticketFile: tempFile())
        try await eventually { anna.state != nil }
        return anna
    }

    /// Over Bonjour, like on real devices: the guests find the new host by the table name.
    @Test func handoverMovesTheTableToAGuest() async throws {
        let name = uniqueName()
        let annaSave: SaveFile<HostSnapshot> = tempFile(), benSave: SaveFile<HostSnapshot> = tempFile()
        let annaTicket: SaveFile<SeatTicket> = tempFile(), benTicket: SaveFile<SeatTicket> = tempFile()
        let service = NWEndpoint.service(name: name, type: Wire.serviceType, domain: "local.", interface: nil)
        let anna = try await TableSession.host(
            .newTable(hostName: "Anna", tableName: name, code: code4711, config: .relaxed),
            saveFile: annaSave, ticketFile: annaTicket)
        let ben = await TableSession.join(endpoint: service, tableName: name, code: code4711, name: "Ben",
                                          ticketFile: benTicket, saveFile: benSave)
        let cem = await TableSession.join(endpoint: service, tableName: name, code: code4711, name: "Cem",
                                          ticketFile: tempFile(), saveFile: tempFile())
        defer { Task { await cem.leave() } }
        try await eventually(timeout: .seconds(30)) {
            anna.state?.seats.count == 3 && ben.me != nil && cem.me != nil && benTicket.load() != nil
        }
        await anna.send(.startTournament(button: anna.me!))
        try await eventually { [anna, ben, cem].allSatisfy { $0.state?.phase == .betting } }

        await anna.send(.transferHost(to: ben.me!))
        try await eventually(timeout: .seconds(30)) { anna.successor != nil && ben.successor != nil }
        let newHost = ben.successor!, oldHost = anna.successor!
        defer { Task { await oldHost.leave(); await newHost.leave() } }
        try await eventually(timeout: .seconds(30)) {
            await newHost.tableHost!.connectedPlayers == [anna.me!, ben.me!, cem.me!]
                && oldHost.connection == .connected && cem.connection == .connected && cem.state?.hostID == ben.me
        }
        #expect(newHost.isHost && newHost.me == ben.me && newHost.tableName == name)
        #expect(!oldHost.isHost && oldHost.me == anna.me)
        #expect(benSave.load()?.game.state.hostID == ben.me && benTicket.load() == nil)
        try await eventually { annaSave.load() == nil }
        #expect(annaTicket.load()?.tableName == name)

        await newHost.send(.pauseClock)
        #expect(newHost.rejection == nil)
        try await eventually { oldHost.state?.clock.isPaused == true }
        await oldHost.send(.resumeClock)
        #expect(oldHost.rejection == .notHost)
    }

    /// The target is a plain client that never hosts, like a crashed app.
    @Test func oldHostKeepsItsSaveUntilTheNewHostAnswers() async throws {
        let save: SaveFile<HostSnapshot> = tempFile()
        let anna = try await hostUnique(save)
        let ben = TableClient(endpoint: .hostPort(host: "127.0.0.1", port: anna.port!), code: code4711, name: "Ben")
        await ben.connect()
        try await eventually { anna.state?.seats.count == 2 }
        await anna.send(.startTournament(button: anna.me!))
        try await eventually { anna.state?.phase == .betting }
        let target = anna.state!.seats[1].id

        await anna.send(.transferHost(to: target))
        try await eventually { anna.successor != nil }
        let retired = anna.successor!
        #expect(!retired.isHost && retired.connection == .reconnecting && retired.state?.phase == .betting)
        #expect(await retired.leave())
        let kept = try #require(save.load())
        #expect(kept.isResumable && kept.game.state.hostID == anna.me)
        await ben.disconnect()
    }

    @Test func failedTakeoverIsShownAndTheGuestStaysAGuest() async throws {
        let anna = try await hostUnique()
        defer { Task { await anna.successor?.leave() } }
        let benSave: SaveFile<HostSnapshot> = tempFile()
        try FileManager.default.createDirectory(at: benSave.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try setReadOnly(benSave, true)
        defer { try? setReadOnly(benSave, false) }
        let ben = await guestSession(anna, saveFile: benSave)
        defer { Task { await ben.leave() } }
        try await eventually { anna.state?.seats.count == 2 && ben.me != nil }
        await anna.send(.startTournament(button: anna.me!))
        try await eventually { anna.state?.phase == .betting && ben.state?.phase == .betting }

        await anna.send(.transferHost(to: ben.me!))
        try await eventually { ben.problem?.action == .listen }
        #expect(ben.successor == nil && !ben.isHost)
        try await eventually { ben.connection == .reconnecting }
    }

    @Test func leavingAsHostStillLeavesTheSeatTicketAlone() async throws {
        let tickets: SaveFile<SeatTicket> = tempFile()
        try tickets.save(SeatTicket(tableName: "Other", code: code4711, name: "Anna", token: "t"))
        let anna = try await hostSession(ticketFile: tickets)
        #expect(await anna.leave())
        #expect(tickets.load()?.tableName == "Other")
    }
}
```

- [ ] **Step 3: Run them and see them fail**

Run: `swift test --filter HandoverTests`
Expected: build error, `extra argument 'ticketFile' in call`.

- [ ] **Step 4: Implement in `TableSession.swift`**

Stored state:

- `public private(set) var successor: TableSession?`, doc comment: "The session that replaces this one after a host handover; nil otherwise. Switch to it as soon as it appears: this session is finished then."
- `private let handoverFiles: (host: SaveFile<HostSnapshot>, seat: SaveFile<SeatTicket>)`: where a successor keeps its files. `saveFile` and `ticketFile` keep their meaning (the files this session owns; nil on the other role), so `leave()` does not change.
- `private var retiredSave: SaveFile<HostSnapshot>?`: set on the guest session of a former host; deleted on its first `welcome`.

Signatures: the private `init` takes `handoverFiles`; `host` gets `ticketFile: SaveFile<SeatTicket> = .seat` and `join` gets `saveFile: SaveFile<HostSnapshot> = .host`, both documented as "used only if a host handover changes this device's role".

Event handling in `handle`:

- `.welcome`: after the existing lines, if `retiredSave` is set, clear it and delete that file through `record(.delete)`.
- `.connectionLost`: after setting `.reconnecting`, if this session has a `tableHost`, check `await tableHost.handedOver` in a `Task` and call `stepDown()` when it is true.
- `.handover(handover)`: `Task { await takeOver(handover) }` (replaces the placeholder from Task 2).

```swift
/// A guest becomes the host: starts the table from the handover and publishes the host session.
private func takeOver(_ handover: Handover) async

/// The former host becomes a guest: publishes a session that reconnects by the table's Bonjour name.
private func stepDown() async

/// Shows the predecessor's table until this session's own first state arrives.
private func adopt(_ old: TableSession)
```

`takeOver`: return if `successor != nil` or `isHost`. Disconnect the client. Build `HostSnapshot(game:tokens:tableName:code:)` from the handover and this session's `tableName` and `code`, then `try await TableSession.host(snapshot, saveFile: handoverFiles.host, ticketFile: handoverFiles.seat)`. On success: cancel `eventTask`, delete `ticketFile` through `record(.delete)`, `next.adopt(self)`, set `successor`. On failure: `record(.listen, error)`, set `connection = .reconnecting` (the client was disconnected by hand, so it reports no `connectionLost`) and `await client.connect()` so the device stays a guest.

`stepDown`: return if `successor != nil`. Cancel `eventTask` and `saveTask`, read `await client.token`, disconnect the client. Build the guest with the private `init` (not `join`, so everything is set before it starts): a `TableClient` on `.service(name: tableName, type: Wire.serviceType, domain: "local.", interface: nil)` with this session's `code`, `name` and token; `tableHost: nil`, `port: nil`, `saveFile: nil`, `ticketFile: handoverFiles.seat`, `fromTicket: true`. Then `next.adopt(self)`, `next.connection = .reconnecting`, `next.retiredSave = handoverFiles.host`, `await next.start()`, set `successor`. Do not call `tableHost.end()` and do not delete the save.

`adopt`: only when `state == nil`, copy `state` and `me` from `old`.

Update the type's doc comment with one sentence on `successor`.

- [ ] **Step 5: Run the tests**

Run: `swift test`
Expected: all pass. `handoverMovesTheTableToAGuest` needs Bonjour on the machine, like `resumeOnNewPortViaBonjour`.

- [ ] **Step 6: Commit**

```bash
git add Sources/PokerSession/TableSession.swift Tests/PokerSessionTests/Helpers.swift Tests/PokerSessionTests/HandoverTests.swift
git commit -m "feat(session): a guest takes the table over and the old host steps down"
```

---

### Task 5: App menu, session swap and docs

**Files:**

- Modify: `App/Sources/HostMenu.swift`, `App/Sources/PokerChipCaseApp.swift`, `README.md`
- Test: none (the app has no unit tests); build and manual checks.

**Interfaces:**

- Consumes: `Command.transferHost(to:)`, `TableSession.successor`.

- [ ] **Step 1: Add the menu entry in `HostMenu.swift`**

- `case handOver(PlayerID, String)` in `HostConfirm`.
- A private `successors: [Seat]`: empty when `state.phase == .finished`, otherwise every seat that is not eliminated and not `state.hostID`.
- After the "Remove player" menu, when `successors` is not empty: `Menu("Hand over table", systemImage: "arrow.left.arrow.right")` with one button per seat that sets `pending = .handOver(seat.id, seat.name)`.
- In `hostConfirmation`: title `"Hand the table over to \(name)? Their phone runs the table from then on."` and `Button("Hand over") { Task { await session.send(.transferHost(to: id)) } }` (no destructive role).

- [ ] **Step 2: Swap the session in `PokerChipCaseApp.swift`**

- `TableScreen(...)` gets `.id(ObjectIdentifier(session))`, so its dialogs and state reset with the new session.
- On the `Group`: `.onChange(of: session?.successor.map(ObjectIdentifier.init)) { if let next = session?.successor { session = next } }`.

- [ ] **Step 3: Add the feature to `README.md`**

In "Features", after the line about the host's table surviving a restart: `- The host can hand the table over to another player's phone and leave`.

- [ ] **Step 4: Run every gate**

```bash
swift test
pre-commit run --all-files
xcodebuild docbuild -scheme PokerChipCase-Package -destination 'generic/platform=macOS' -derivedDataPath .build/docs OTHER_DOCC_FLAGS=--warnings-as-errors -quiet
xcodegen generate --spec App/project.yml
xcodebuild build -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: all five exit 0 with no warnings from the doc build.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/HostMenu.swift App/Sources/PokerChipCaseApp.swift README.md
git commit -m "feat(app): hand the table over from the host menu"
```

- [ ] **Step 6: List the manual checks in the PR body, unticked**

iPhone as host, two simulators as guests, digital cards on:

- [ ] Hand over mid-hand to a simulator: both other devices show "Reconnecting…" briefly and then the same hand; the new host has the host menu, the old host does not.
- [ ] The new host pauses the clock and undoes the last action; the old host's phone follows.
- [ ] The old host taps "Leave table"; the game goes on and the new host can fold for them.
- [ ] Target app in the background for more than 12 s: the banner shows "That player's app is not open" and the table keeps running.
- [ ] Target killed right after the handover: the old host taps "Leave table", then "Resume game"; the other guest returns.
