# Audit Findings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the four findings of the 2026-11-16 repo audit: an undone removal locks the player out, the host accepts names of any length, the host menu lists players already removed this hand, and the lobby runs a second Bonjour browser.

**Architecture:** Tokens stop being deleted on removal; the host accepts a token only while its player still has a seat, and a guest keeps its seat ticket after `removed`, so an undo plus "Rejoin" gives the seat back. The host cuts guest names at the trust boundary in `TableHost.welcome`. PokerCore gets one `Seat.isOut` property that both the `removePlayer` rule and the host menu use. The app passes its one `NearbyTables` down to the lobby.

**Tech Stack:** Swift 6, Swift Testing, Network.framework, SwiftUI (iOS 17).

**Spec:** No separate spec. The findings below are the audit's, verbatim in substance.

## Background (the audit findings)

1. `TableHost.forget` and `forgetRemovedPlayers` delete a removed player's token, and `TableSession` deletes the guest's ticket on `.failed(.removed)`. `undo` brings the seat back, but nobody can reconnect to it: mid-game a new `hello` gets `gameInProgress`, in the lobby it joins as a second seat.
2. `TableHost.welcome` seats `hello.name` unchecked. Two names of ~600 KB push every `state` past `MessageChannel.maxMessageSize` (1 MB) and every client loops reconnecting. Empty names are accepted too.
3. A player removed mid-hand stays folded with 0 chips until the hand ends. `HostMenu.removable` and `successors` still list them; removing again adds a no-op undo step, handing over always fails with `playerOffline`.
4. `LobbyView` creates its own `NearbyTables` only to read `localNetworkDenied`, while `PokerChipCaseApp.nearby` already browses for the whole app life.

## Global Constraints

- Swift 6 language mode; fix concurrency errors, never silence them.
- Code, comments, docs, commits in English; Conventional Commits, e.g. `fix(net): …`.
- `Wire.version` stays 3: no wire-format change. `Protocol.md` changes in the same PR as the behavior it describes.
- Before the PR: `pre-commit run --all-files`, `swift test`, the docbuild command and the app build from `AGENTS.md`.
- Keep existing `ponytail:` comments in touched code.

## Review Focus

1. A removed player (not undone) reconnects with the old token mid-game: they get their folded, 0-chip seat back as a spectator and cannot act. Expected and acceptable; pinned in Task 1's net test.
2. A player removed in the lobby reconnects with the old token: the seat is gone, so they join as a new player (new ID), exactly as before. Pinned by the updated `removedPlayerIsDisconnectedAndForgotten`.
3. An undone lobby join: the guest still gets `removed` and its connection closes (`forgetRemovedPlayers` keeps the kick). Existing tests cover it; they must stay green.
4. A name of only spaces or newlines becomes "Player"; a name with multi-scalar emoji is cut by `Character`, never mid-grapheme. Pinned in Task 2.
5. A player who is all-in has 0 chips but is not folded: they must not count as out. Pinned in Task 3.

Accepted side effect: a removed guest whose removal is never undone keeps a "Rejoin" entry on the start screen until they tap "Discard" or the rejoin fails; rejoining shows their out seat or, in the lobby, seats them anew.

---

### Task 1: An undone removal gives the seat back

**Files:**

- Modify: `Sources/PokerNet/TableHost.swift:251-252`, `:271-284`, `:292`
- Modify: `Sources/PokerSession/TableSession.swift:279-282`
- Modify: `Sources/PokerNet/PokerNet.docc/Protocol.md:54`, `:181`
- Test: `Tests/PokerNetTests/HostCommandTests.swift`, `Tests/PokerSessionTests/SessionTests.swift`

**Interfaces:**

- Produces: `TableHost.welcome` accepts a token only if `snapshot.game.state.seat(player) != nil`; tokens are never deleted. `forget(_:)` is renamed `kick(_ player: PlayerID)` and only sends `removed` and closes; `forgetRemovedPlayers()` is renamed `kickUnseatedPlayers()` and only closes connections of unseated players.

- [ ] **Step 1: Update the two existing net tests and add the undo test**

In `removedPlayerIsDisconnectedAndForgotten` (lobby) replace `#expect(await t.host.snapshot.tokens[t.benWelcome.token] == nil)` with nothing; the existing "reconnect joins as a new player" assertion stays and now proves the seat check. Rename it `removedPlayerIsDisconnectedAndRejoinsAsNew`.

In `removedMidGameIsDisconnectedAndForgotten` rename it `removedMidGameIsDisconnectedAndKeepsTheToken` and replace the token assertion with `#expect(await t.host.snapshot.tokens[t.benWelcome.token] == t.benWelcome.player)`.

Add:

```swift
@Test func undoneRemovalLetsThePlayerReconnect() async throws {
    let t = try await Table.open()
    let cem = try await RawClient.connect(t.port)
    cem.send(hello("Cem"))
    _ = try await cem.welcome()
    let state = try await t.anna.state { $0.seats.count == 3 }
    t.anna.send(t.command(.startTournament(button: t.hostID), version: state.version))
    let running = try await t.anna.state { $0.phase == .betting }
    t.anna.send(t.command(.removePlayer(player: t.benWelcome.player), version: running.version))
    try await t.ben.waitForClose()
    let removed = try await t.anna.state { $0.version > running.version }
    t.anna.send(t.command(.undo, version: removed.version))
    _ = try await t.anna.state { $0.version > removed.version }
    let again = try await RawClient.connect(t.port)
    again.send(hello("Ben", token: t.benWelcome.token))
    #expect(try await again.welcome().player == t.benWelcome.player)
    #expect(try await again.state().seat(t.benWelcome.player)?.stack ?? 0 > 0)
    await t.host.stop()
}
```

- [ ] **Step 2: Run them, expect failures**

Run: `swift test --filter HostCommandTests`
Expected: `removedMidGameIsDisconnectedAndKeepsTheToken` and `undoneRemovalLetsThePlayerReconnect` FAIL (token is nil; the reconnect gets `gameInProgress`).

- [ ] **Step 3: Change `TableHost`**

- `handle`: call `kick(removed)` and `kickUnseatedPlayers()` instead of the two `forget` calls.
- `kick`: drop the `snapshot.tokens = …` line; doc: "A player removed mid-game keeps the seat (folded, out) and the token, so an undo can give the seat back; the connection closes."
- `kickUnseatedPlayers`: drop the `snapshot.tokens = …` line; doc: "Players without a seat (removed in the lobby, or their join was undone) lose their connection. Their token stays, but `welcome` only honors tokens of seated players."
- `welcome`: `if let t = hello.token, let p = snapshot.tokens[t], snapshot.game.state.seat(p) != nil {`.

- [ ] **Step 4: Run the net tests**

Run: `swift test --filter PokerNetTests`
Expected: all PASS.

- [ ] **Step 5: Session test: the guest keeps its ticket after `removed`**

Add to `SessionTests`:

```swift
@Test func removedGuestKeepsTicketAndRejoinsAfterUndo() async throws {
    let anna = try await hostSession()
    defer { Task { await anna.leave() } }
    let tickets: SaveFile<SeatTicket> = tempFile()
    let ben = await guestSession(anna, ticketFile: tickets)
    try await eventually { anna.state?.seats.count == 2 && ben.state?.seats.count == 2 }
    await anna.send(.startTournament(button: anna.me!))
    try await eventually { ben.state?.phase == .betting }
    let benID = try #require(ben.me)
    await anna.send(.removePlayer(player: benID))
    try await eventually { ben.connection == .failed(.removed) }
    #expect(await ben.leave())  // the app's alert OK calls leave()
    let ticket = try #require(tickets.load())
    await anna.send(.undo)
    let back = await guestSession(anna, token: ticket.token, ticketFile: tickets)
    try await eventually { back.connection == .connected }
    #expect(back.me == benID)
}
```

In `guestLeavingTheLobbyFreesTheSeat` delete `#expect(await anna.tableHost!.snapshot.tokens.count == 1)`; tokens are no longer pruned, the seat count above it is the real check.

- [ ] **Step 6: Run it, expect failure**

Run: `swift test --filter removedGuestKeepsTicketAndRejoinsAfterUndo`
Expected: FAIL at `#require(tickets.load())`.

- [ ] **Step 7: Change `TableSession.handle(.failed)` and `leave()`**

`handle(.failed)`: delete the ticket only when `failure != .removed`; one-line comment: "After `removed` the ticket stays: an undo by the host gives the seat back to it."
`leave()`: delete `ticketFile` only when `connection != .failed(.removed)` (the save file as before). Update its doc comment to say so.

- [ ] **Step 8: Update `Protocol.md`**

Line 54: after "An unknown token counts as a new join." add "So does the token of a player who no longer has a seat."
Line 181 (`removed` row): replace "the token is no longer valid" with "the token stays valid while the seat exists, so an `undo` by the host gives the seat back".

- [ ] **Step 9: Run everything**

Run: `swift test`
Expected: all PASS.

- [ ] **Step 10: Commit**

```bash
git add Sources/PokerNet/TableHost.swift Sources/PokerSession/TableSession.swift Sources/PokerNet/PokerNet.docc/Protocol.md Tests/PokerNetTests/HostCommandTests.swift Tests/PokerSessionTests/SessionTests.swift
git commit -m "fix(net): keep tokens on removal so an undo gives the seat back"
```

### Task 2: The host cuts guest names

**Files:**

- Modify: `Sources/PokerNet/TableHost.swift:301` (in `welcome`)
- Modify: `Sources/PokerNet/PokerNet.docc/Protocol.md:54`
- Test: `Tests/PokerNetTests/HostLobbyTests.swift`

**Interfaces:**

- Produces: `static let maxNameLength = 32` on `TableHost`; `static func seatName(_ raw: String) -> String` on `TableHost` (internal): trims whitespace and newlines, keeps the first 32 `Character`s, returns `"Player"` if empty.

- [ ] **Step 1: Write the tests**

```swift
@Test func seatNameIsTrimmedCutAndNeverEmpty() {
    #expect(TableHost.seatName("  Ben \n") == "Ben")
    #expect(TableHost.seatName(String(repeating: "x", count: 1000)) == String(repeating: "x", count: 32))
    #expect(TableHost.seatName(String(repeating: "👨‍👩‍👧", count: 40)).count == 32)
    #expect(TableHost.seatName(" \n ") == "Player")
}

@Test func longNameIsCutOnJoin() async throws {
    let (host, port) = try await startHost()
    let ben = try await RawClient.connect(port)
    ben.send(hello(String(repeating: "B", count: 100_000)))
    let w = try await ben.welcome()
    #expect(try await ben.state().seat(w.player)?.name.count == TableHost.maxNameLength)
    await host.stop()
}
```

- [ ] **Step 2: Run, expect a compile failure**

Run: `swift test --filter HostLobbyTests`
Expected: FAIL, `seatName` / `maxNameLength` not found.

- [ ] **Step 3: Implement `seatName` and use it**

In `welcome`, apply `.join(player: player, name: Self.seatName(hello.name))`. Doc comment on `maxNameLength`: "Names longer than this would bloat every state message; the app's field never needs more."

- [ ] **Step 4: Document it**

`Protocol.md` line 54, after the `payload.token` sentence: "The host trims `payload.name`, cuts it to 32 characters and uses `Player` if nothing is left."

- [ ] **Step 5: Run the tests**

Run: `swift test --filter PokerNetTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/PokerNet/TableHost.swift Sources/PokerNet/PokerNet.docc/Protocol.md Tests/PokerNetTests/HostLobbyTests.swift
git commit -m "fix(net): cut guest names to 32 characters at the host"
```

### Task 3: A player removed this hand counts as out

**Files:**

- Modify: `Sources/PokerCore/Types.swift:104-105` (next to `isEliminated`)
- Modify: `Sources/PokerCore/Game.swift:96`
- Modify: `App/Sources/HostMenu.swift:26-34`
- Test: `Tests/PokerCoreTests/HandEndTests.swift`

**Interfaces:**

- Produces: `public var isOut: Bool { isEliminated || (folded && stack == 0) }` on `Seat`. Doc: "True once the player no longer plays: eliminated, or removed by the host in the current hand. Only a removed player folds with no chips; an all-in player has no chips but has not folded."

- [ ] **Step 1: Write the tests**

```swift
@Test func removedPlayerIsOutAndCannotBeRemovedAgain() throws {
    var g = try Game.started()
    try g.apply(.removePlayer(player: "B"), by: "A", at: t0)
    #expect(g.state.seat("B")?.isOut == true && g.state.seat("B")?.isEliminated == false)
    #expect(throws: Rejection.unknownPlayer) { try g.apply(.removePlayer(player: "B"), by: "A", at: t0) }
}

@Test func allInPlayerIsNotOut() throws {
    var g = try Game.started()
    try g.act(.allIn)
    #expect(g.state.seat("A")?.stack == 0 && g.state.seat("A")?.isOut == false)
}
```

- [ ] **Step 2: Run, expect a compile failure**

Run: `swift test --filter HandEndTests`
Expected: FAIL, `isOut` not found.

- [ ] **Step 3: Implement**

Add `isOut` to `Seat`. In `Game.swift` `.removePlayer`, change `!seats[i].isEliminated` to `!seats[i].isOut`. In `HostMenu`, both `removable` and `successors` filter with `!$0.isOut` instead of `!$0.isEliminated`.

- [ ] **Step 4: Run all package tests**

Run: `swift test`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PokerCore/Types.swift Sources/PokerCore/Game.swift App/Sources/HostMenu.swift Tests/PokerCoreTests/HandEndTests.swift
git commit -m "fix(core): a player removed this hand cannot be removed or picked again"
```

### Task 4: The lobby uses the app's browser

**Files:**

- Modify: `App/Sources/PokerChipCaseApp.swift:17`
- Modify: `App/Sources/TableScreen.swift:6-20`, `:34`
- Modify: `App/Sources/LobbyView.swift:11`, `:19-22`, `:103`

**Interfaces:**

- Produces: `TableScreen(session: TableSession, nearby: NearbyTables, onLeave: @escaping () -> Void)`; `LobbyView(session: TableSession, state: GameState, nearby: NearbyTables)`; both store `let nearby: NearbyTables`.

- [ ] **Step 1: Pass `nearby` down**

`PokerChipCaseApp` passes its `nearby` to `TableScreen`; `TableScreen` passes it to `LobbyView`. In `LobbyView` replace `@State private var nearby = NearbyTables()` with `let nearby: NearbyTables` and delete `.task { if session.isHost { await nearby.run() } }`. The app-level `.task { await nearby.run() }` already browses for the whole app life.

- [ ] **Step 2: Build the app**

Run the app build from `AGENTS.md` (`xcodegen generate --spec App/project.yml` then `xcodebuild build … -quiet`).
Expected: exit 0, no warnings in the touched files.

- [ ] **Step 3: Commit**

```bash
git add App/Sources/PokerChipCaseApp.swift App/Sources/TableScreen.swift App/Sources/LobbyView.swift
git commit -m "refactor(app): the lobby reads the app's table browser"
```

### Task 5: Gates and PR

- [ ] **Step 1: Run the four gates from `AGENTS.md`**

`pre-commit run --all-files`, `swift test`, the docbuild command, the app build. Expected: all exit 0.

- [ ] **Step 2: Open the PR**

Body links this plan and lists manual checks, unticked: on a real iPhone as host plus one simulator guest, (a) remove the guest mid-hand, undo, tap "Rejoin" on the guest: the seat and chips come back; (b) after removing a guest, the host menu no longer lists them under "Remove player" or "Hand over table"; (c) with local network access denied, the lobby still shows the notice.
