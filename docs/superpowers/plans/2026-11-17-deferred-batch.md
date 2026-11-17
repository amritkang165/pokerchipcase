# Deferred Issues Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the open `deferred` issues #125, #121, #126, #128, #127, #134, #132, #113, #133 and #111 in three PRs.

**Architecture:** There are three PRs:

- PR 1 (`fix(net)`, branch `fix/deferred-net`) holds Tasks 1–4. It has no manual checks, so it can auto-merge.
- PR 2 (`fix(app)`, branch `fix/deferred-app`) holds Tasks 5–8 and ends with manual checks on an iPhone.
- PR 3 (`docs`, branch `docs/english-screenshots`) holds Task 9. It starts after PR 2 is merged, so the screenshots show the new inks and the new felt edge.

PRs 1 and 2 can run in parallel worktrees. Both touch `Sources/PokerNet/TableHost.swift` and `Tests/PokerNetTests/HostLobbyTests.swift`, but in different hunks. Whichever PR merges second rebases first.

**Tech Stack:** Swift 6, Swift Testing, Network.framework, SwiftUI, xcodegen, simctl, headless Chrome.

**Spec:** The GitHub issues themselves. Their findings were checked on 2026-11-17 and the results are below.

## Findings checked before planning

- **#125, timing:** Four plain runs of `swift test` were all green. Under CPU load (`yes` on every core), 5 of 15 runs failed, each time in `connectionWithoutHelloIsClosedAfterTimeout` with `TimeoutError`. With `helloTimeout` raised from 300 ms to 2 s, that test failed 0 of 15 times.
- **#125, handover bug:** In those 15 runs, `silentTargetIsRejectedUntilItPings` failed once. Instrumented, it hung in the second `t.anna.ack()`, the one where the transfer is accepted. The cause is a real host bug: `MessageChannel.send` only queues `connection.send`, and `finishHandover` then calls `disconnectAll()`, which cancels each connection at once.
- **#125, probe:** A channel probe confirmed the cause. With `send` followed at once by `cancel()`, 0 of 8 messages arrived, at 200 B and at 1 MiB. A final empty send (`.finalMessage`, `isComplete: true`) with `cancel()` in its `contentProcessed` completion delivered 4 of 4. The handover usually works only because `await cancelListener()` delays the cancel.
- **#121:** `handoverWithFiftyUndoStepsFitsOneMessage` (`Tests/PokerCoreTests/WireTests.swift:104`) sets `g.history` by hand and never calls `keepHistory`.
- **#126:** `welcome` (`Sources/PokerNet/TableHost.swift:302`) gives a known token without a seat a new player ID and a new token.
  - Fix: rejoin under the old ID with the old token. An undo of the removal then finds the token again.
  - `Game` allows this, because `.join` only rejects an ID that is seated.
  - Three places describe the old behavior and change with it: the test `removedPlayerIsDisconnectedAndRejoinsAsNew` (`Tests/PokerNetTests/HostCommandTests.swift:53`), the doc comment of `kickUnseatedPlayers` (`TableHost.swift:294`), and `Protocol.md:54` and `:181`.
  - The wire format does not change.
- **#128:** After #126, a rejoin with a token adds no token. It does not stop the growth #128 describes. A voluntary lobby leave deletes the seat ticket, because `TableSession.leave` keeps it only after `.removed` (`TableSession.swift:219`). The next join then has no token and adds one. The issue offers a code comment as the fix, and the comment uses the repo's `ponytail:` convention (AGENTS.md; 13 uses, no `shortcut:` comment).
- **Residual, out of scope:** A voluntary lobby leave followed by an undo of that leave still restores a seat that no ticket holds. The PR body for #126 names this limit.
- **#127:** `TableHost.seatName` and `HostSnapshot.newTable` are both in `PokerNet`, so `newTable` can call the internal `seatName`. `StartView` imports `PokerNet`, but `maxNameLength` is internal and must become `public`. The deployment target is iOS 17, which has the two-parameter `onChange`.
- **#134, contrast:** Contrast was computed on the seat fill composited over the felt.
  - On every dark stage the inks of the cream card reach only red `c0392b` 3.31–3.67, blue `1f5fbf` 2.95–3.29 and green `1b7a40` 3.35–3.73.
  - Neon dark's card inks reach `ff6b6b` ≥ 6.48, `6aa5ff` ≥ 7.23 and `4cc47a` ≥ 8.13.
  - On light stages the current inks reach ≥ 4.54.
- **#134, where:** Both real uses (`RoundTable.swift:113`, `RankingView.swift:53`) sit on `theme.seat`. `TableSurface.swift:18` already derives a dark stage from `colorScheme`.
- **#132:** Owner decision: fix it. The felt radius is `(0.5 − 0.105 − cushionWidth) · d`. That is 0.385 d for Felt, Neon and Rubin and 0.37 d for Royal.
- **#111:** Owner decision: close as won't fix.
- **#133:** The mockup sources exist locally: `.superpowers/brainstorm/79585-1794858420/content/cards-final.html` and `themes-final.html` (identical to `themes-final-2.html`).
  - Wrapping a mockup into the Superpowers `frame-template.html` (replace `<!-- CONTENT -->`) and rendering it with headless Chrome 157 was tested and works.
  - The old images are 1300×1150 (cards) and 1196×1300 (themes).
  - `scripts/readme-screenshots.sh:29` launches the app without a language or locale.
- **#129** is not in this plan. It needs a brainstorm, a mockup and a spec first (see the issue).

## Global Constraints

- Swift 6 language mode; no concurrency warnings silenced.
- Code, comments, docs and commits in English; Conventional Commits.
- `Protocol.md` changes in the same PR as the behavior it describes.
- Before each PR: `pre-commit run --all-files`, `swift test`, the docs build and the app build from AGENTS.md.
- Each PR body lists the ticked automatic gates and the unticked manual checks, and links this plan.
- Tasks marked "inline" take at most three tool calls. The controller does them itself, without a subagent (global CLAUDE.md).

## Review Focus

1. A seatless token that rejoins while a tournament runs must get `gameInProgress` and add no token. Test in Task 4.
2. Two devices with the same seatless token: after the first one rejoins, the second takes the seat and the first one gets `replaced`. There must never be a second seat. The first branch of `welcome` covers this once the player is seated again. The Task 4 reviewer checks the branch order.
3. Graceful close: if a peer's send buffer stays full, `contentProcessed` may never fire and that connection never closes. `sendAndClose` already carries this risk. The reviewer checks that `stop()` and `end()` keep the hard cancel.
4. A name of exactly 32 characters made of ZWJ emoji: the TextField cuts by characters, and the host also cuts by bytes. The host's name must match what guests see. Test in Task 5.
5. Four-color off on a dark stage: hearts and diamonds must use `ff6b6b`, and spades and clubs must keep `seatText`. Checked manually in Task 8.

---

### Task 1: Hello-timeout test with a margin (#125, part 1)

**Implementer:** inline.

**Files:**

- Modify: `Tests/PokerNetTests/HostLobbyTests.swift:110`

- [ ] **Step 1:** Change `startHost(helloTimeout: .milliseconds(300))` to `startHost(helloTimeout: .seconds(2))` and add this comment above it: `// Ben's TLS handshake and hello must fit in the timeout even when the full suite loads the CPU (#125).`
- [ ] **Step 2:** Run `swift test --filter connectionWithoutHelloIsClosedAfterTimeout`. Expected: PASS, in about 2 s.
- [ ] **Step 3: Commit:** `test(net): give the hello timeout test a margin under load`

### Task 2: Handover closes connections after their queued messages (#125, part 2)

**Implementer:** opus high (networking). **Reviewer:** opus high.

**Files:**

- Modify: `Sources/PokerNet/MessageChannel.swift` (next to `sendAndClose`, line 62)
- Modify: `Sources/PokerNet/TableHost.swift:149` (`disconnectAll`), `:284` (`finishHandover`)
- Test: `Tests/PokerNetTests/ChannelTests.swift`, next to `messageAtTheLimitArrives`

**Interfaces:**

- Produces: `MessageChannel.close()`, which closes once every message queued before it has been handed to the network stack. Also `TableHost.disconnectAll(graceful: Bool = false)`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func closeDeliversWhatWasQueuedBefore() async throws {
    let (listener, port, channels) = try await startRecordingListener()
    defer { listener.cancel() }
    let sender = MessageChannel(to: loopback(port), code: code4711)
    let rec = EventRecorder(sender.events)
    sender.start()
    _ = try await rec.first { $0 == .ready }
    let big = Data(repeating: UInt8(ascii: "a"), count: MessageChannel.maxMessageSize)
    sender.send(big)
    sender.close()
    var it = channels.makeAsyncIterator()
    let receiver = try #require(await it.next())
    _ = try await receiver.first { $0 == .message(big) }
}
```

- [ ] **Step 2:** Run `swift test --filter closeDeliversWhatWasQueuedBefore`. Expected: a compile error, because `close()` does not exist yet.
- [ ] **Step 3: Implement `func close()` in `MessageChannel`.** On `queue`, call `connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [connection] _ in connection.cancel() })`. Sends on one connection keep their order, so everything queued before goes out first. Doc comment: one line, as in the Interfaces block.
- [ ] **Step 4: Add `graceful: Bool = false` to `disconnectAll`.** With `true`, call `close()` on each channel instead of `cancel()`. `finishHandover` calls `disconnectAll(graceful: true)`. `stop()` and the test callers keep the hard cancel, because a stopped host must not wait for anyone.
- [ ] **Step 5:** Run `swift test --filter ChannelTests` and then `swift test`. Expected: all green.
- [ ] **Step 6: Run the load loop as a smoke check.** It is not proof: before the fix, the handover test failed about 1 run in 15. Expected: `fails=0/25`.

```sh
swift build --build-tests
L=$(mktemp -d); for c in $(seq $(sysctl -n hw.ncpu)); do (yes >/dev/null &); done
fails=0; for i in $(seq 25); do swift test --skip-build >"$L/$i.log" 2>&1 || { fails=$((fails+1)); grep "✘ Test" "$L/$i.log" | head -2; }; done
pkill -x yes; echo "fails=$fails/25"
```

- [ ] **Step 7: Commit:** `fix(net): let the handover ack reach the sender before the host closes`

### Task 3: Handover size test runs keepHistory (#121)

**Implementer:** inline.

**Files:**

- Modify: `Tests/PokerCoreTests/WireTests.swift:109`

- [ ] **Step 1:** Replace `g.history = Array(repeating: g.state, count: 50)` with:

```swift
g.history = Array(repeating: g.state, count: 60)
g.keepHistory(last: 50)  // TableHost.handoverHistory
#expect(g.history.count == 50)
```

- [ ] **Step 2:** Run `swift test --filter handoverWithFiftyUndoStepsFitsOneMessage`. Expected: PASS.
- [ ] **Step 3: Commit:** `test(core): run the handover size check through keepHistory`

### Task 4: Lobby rejoin keeps the old player ID (#126, #128)

**Implementer:** opus high (protocol and state). **Reviewer:** opus high.

**Files:**

- Modify: `Sources/PokerNet/TableHost.swift:292-330` (`kickUnseatedPlayers`, `welcome`)
- Modify: `Sources/PokerNet/PokerNet.docc/Protocol.md:54`, `:181`
- Test: `Tests/PokerNetTests/HostCommandTests.swift:53`

- [ ] **Step 1: Rewrite the old test and add two new ones**

Replace `removedPlayerIsDisconnectedAndRejoinsAsNew` with:

```swift
@Test func removedPlayerRejoinsUnderTheOldID() async throws {
    let t = try await Table.open()
    t.anna.send(t.command(.removePlayer(player: t.benWelcome.player)))
    #expect(try await t.ben.error() == WireErrorCode.removed.rawValue)
    try await t.ben.waitForClose()
    let again = try await RawClient.connect(t.port)
    again.send(hello("Ben", token: t.benWelcome.token))
    #expect(try await again.welcome() == t.benWelcome)
    #expect(await t.host.snapshot.tokens.count == 2)
    await t.host.stop()
}

@Test func undoAfterALobbyRejoinLeavesNoGhost() async throws {
    let t = try await Table.open()
    t.anna.send(t.command(.removePlayer(player: t.benWelcome.player)))
    try await t.ben.waitForClose()
    let again = try await RawClient.connect(t.port)
    again.send(hello("Ben", token: t.benWelcome.token))
    let ticket = try await again.welcome()  // the app overwrites its seat ticket with this
    let rejoined = try await t.anna.state { $0.seats.count == 2 }
    t.anna.send(t.command(.undo, version: rejoined.version))
    #expect(try await again.error() == WireErrorCode.removed.rawValue)
    let undone = try await t.anna.state { $0.version > rejoined.version }
    t.anna.send(t.command(.undo, version: undone.version))
    let restored = try await t.anna.state { $0.version > undone.version }
    #expect(restored.seats.map(\.id) == [t.hostID, t.benWelcome.player])
    let back = try await RawClient.connect(t.port)
    back.send(hello("Ben", token: ticket.token))
    #expect(try await back.welcome().player == t.benWelcome.player)
    await t.host.stop()
}

@Test func seatlessTokenCannotJoinARunningGame() async throws {
    let t = try await Table.open()
    let cem = try await RawClient.connect(t.port)
    cem.send(hello("Cem"))
    _ = try await cem.welcome()
    let three = try await t.anna.state { $0.seats.count == 3 }
    t.anna.send(t.command(.removePlayer(player: t.benWelcome.player), version: three.version))
    let two = try await t.anna.state { $0.seats.count == 2 }
    t.anna.send(t.command(.startTournament(button: t.hostID), version: two.version))
    _ = try await t.anna.state { $0.phase == .betting }
    let again = try await RawClient.connect(t.port)
    again.send(hello("Ben", token: t.benWelcome.token))
    #expect(try await again.error() == WireErrorCode.gameInProgress.rawValue)
    #expect(await t.host.snapshot.tokens.count == 3)
    await t.host.stop()
}
```

- [ ] **Step 2:** Run `swift test --filter HostCommandTests`. Expected:
  - `removedPlayerRejoinsUnderTheOldID` FAILS, because the player ID differs.
  - `undoAfterALobbyRejoinLeavesNoGhost` FAILS on its last expectation, because the new token belongs to the undone seat.
  - `seatlessTokenCannotJoinARunningGame` passes already.
- [ ] **Step 3: Change the `else` branch of `welcome`.** A known token keeps its player ID: `let known = hello.token.flatMap { snapshot.tokens[$0] }` and `player = known ?? UUID().uuidString`. Mint and store a new token only when `known == nil`; otherwise reuse `hello.token`. Comment: `// A removed player rejoins under the old ID and token, so undoing the removal finds them again (#126).`
- [ ] **Step 4: Rewrite the doc comment of `kickUnseatedPlayers`.** The second line ("Their token stays, but `welcome` only honors tokens of seated players.") becomes: ``/// Their token stays: in the lobby, `welcome` seats them again under the old ID.`` Below the doc comment, add `// ponytail: tokens are never pruned; each tokenless join (also after a voluntary leave) adds about 80 bytes to every save and handover. Prune tokens whose player is neither seated nor in Game.history if saves grow noticeably (#128).`
- [ ] **Step 5: Update `Protocol.md`.**
  - Line 54: replace "So does the token of a player who no longer has a seat." with "The token of a player who no longer has a seat (removed in the lobby) joins again under its old player ID and keeps the token, so an `undo` of the removal gives that seat back."
  - Line 181: replace "the token stays valid while the seat exists, so an `undo` by the host gives the seat back" with "the token stays valid: an `undo` by the host gives the seat back, and in the lobby the token can join again".
- [ ] **Step 6:** Run `swift test` and the docs build. Expected: all green, including the three tests from Step 1.
- [ ] **Step 7: Commit:** `fix(net): a removed player rejoins under the old ID`. The PR body closes #126 and #128 and names the residual from the findings: voluntary leave plus undo.

### Task 5: Name limit for the host and the name field (#127)

**Implementer:** sonnet medium.

**Files:**

- Modify: `Sources/PokerNet/TableHost.swift:41-42` (`maxNameLength` becomes `public`)
- Modify: `Sources/PokerNet/HostSnapshot.swift:24-35` (`newTable`)
- Modify: `App/Sources/StartView.swift:35`
- Test: `Tests/PokerNetTests/HostLobbyTests.swift`, next to `seatNameIsTrimmedCutAndNeverEmpty` (line 64)

- [ ] **Step 1: Write the failing test**

```swift
@Test func newTableCutsTheHostNameLikeAGuestName() {
    let long = String(repeating: "👨‍👩‍👧", count: 40)
    let s = HostSnapshot.newTable(hostName: long, tableName: "T", config: .relaxed)
    #expect(s.game.state.seats.first?.name == TableHost.seatName(long))
}
```

- [ ] **Step 2:** Run `swift test --filter newTableCutsTheHostNameLikeAGuestName`. Expected: FAIL.
- [ ] **Step 3: Cut the host name.** `newTable` passes `TableHost.seatName(hostName)` to `Game(hostID:hostName:config:)`, and its doc comment says the name is cut like a guest's. `maxNameLength` becomes `public static let`. Its doc comment becomes "Longest seat name, in characters; the host cuts longer names, which bloat every state message."
- [ ] **Step 4: Limit the name field.** On the `TextField("Name", …)` in `StartView`, add `.onChange(of: playerName) { _, new in if new.count > TableHost.maxNameLength { playerName = String(new.prefix(TableHost.maxNameLength)) } }`.
- [ ] **Step 5:** Run `swift test`, the docs build and the app build. Expected: all green, no DocC warning.
- [ ] **Step 6: Commit:** `fix(app): cut names to 32 characters for host and guest alike`

### Task 6: Readable inline card inks on dark stages (#134)

**Implementer:** inline.

**Files:**

- Modify: `App/Sources/CardViews.swift:179-201` (`CardsText`)

- [ ] **Step 1: Pick the inks in `CardsText`.** Add `@Environment(\.colorScheme) private var scheme`. Before the loop, add `let inks = scheme == .dark ? ThemeName.neon.palette(for: .dark) : theme` and use `inks.suitColor(card.suit, fourColor: fourColor)`. Comment: `// On a dark seat the cream card's inks reach about 3:1; Neon dark's card inks reach 6.5:1 or more (#134).`
- [ ] **Step 2:** Run the app build. Expected: no errors and no warnings.
- [ ] **Step 3: Commit:** `fix(app): lighter suit inks in seat labels on dark stages`

### Task 7: Felt gradient reaches the felt edge (#132)

**Implementer:** inline.

**Files:**

- Modify: `App/Sources/TableSurface.swift:32`

- [ ] **Step 1:** Change `endRadius: d * 0.5` to `endRadius: d * (0.5 - Self.rail - theme.cushionWidth)` and comment it: `// The felt's own radius, so its edge gets the darkest stop (#132).`
- [ ] **Step 2:** Run the app build. Expected: no errors and no warnings. Task 8 checks the look.
- [ ] **Step 3: Commit:** `fix(app): felt gradient ends at the felt edge`

### Task 8: PR 2 manual checks, #113 and #111

**Implementer:** inline (main session).

- [ ] **Step 1: Write the PR body.** The automatic gates are ticked. These manual checks stay unticked and are done on the iPhone. The launch arguments go into the Xcode scheme.
  - Name field: typing stops at 32 characters. A host with a longer saved name shows the same cut name that guests see.
  - #134: run with `-debugTable -digitalCards YES -debugStop payout -fourColorDeck YES -appearance dark`, once each with `-theme felt`, `ruby` and `royal`, then once with `-fourColorDeck NO`. The suits in the seat labels read clearly. `RankingView` uses the same `CardsText` on the same `theme.seat` and needs no separate check.
  - #132: the felt darkens all the way to the cushion on all four themes, light and dark.
  - #113: at a digital table, VoiceOver reads "Your cards, hidden". The "Show cards" action turns the cards up and reads them. Running it again hides them. The next hand starts hidden.
- [ ] **Step 2: Close #111:** `gh issue close 111 --reason "not planned" --comment "Readability is fine either way; a per-row fix would touch about 17 rows in 3 files. Closed as won't fix."`
- [ ] **Step 3:** Merge only once every box is ticked. Close #113 in the PR body when its check is ticked.

### Task 9: English screenshots (#133), PR 3

**Implementer:** sonnet medium. Starts after PR 2 is merged.

**Files:**

- Modify: `scripts/readme-screenshots.sh:29`
- Modify: `docs/images/*.png` (regenerated)
- Modify: `docs/superpowers/specs/images/2026-11-16-cards.jpg`, `2026-11-16-themes.jpg`
- Modify: `docs/superpowers/specs/2026-11-16-themes-and-cards-design.md:20`

- [ ] **Step 1: Pin the language.** Add `-AppleLanguages "(en)" -AppleLocale en_US` to the `simctl launch` line.
- [ ] **Step 2: Take the README shots again.** Run the app build from AGENTS.md, then `scripts/readme-screenshots.sh`. Expected: six PNGs, each under 500 KB. `lobby.png` shows "1,000 chips", not "1.000 chips".
- [ ] **Step 3: Translate the mockups.** Copy `cards-final.html` and `themes-final.html` from `.superpowers/brainstorm/79585-1794858420/content/` into a scratch directory and translate every German string into English. For example: "Hell"→"Light", "Dunkel"→"Dark", "Dein Stack"→"Your stack", "echte Größe"→"actual size". German number formats such as "1.250" become "1,250". The scratch copies stay local.
- [ ] **Step 4: Render the images.**
  - Wrap each mockup into `~/.claude/plugins/cache/superpowers-dev/superpowers/7.0.2/skills/brainstorming/scripts/frame-template.html` by replacing `<!-- CONTENT -->`.
  - Render with `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --hide-scrollbars --window-size=1300,1150 --screenshot=<out>.png file://<wrapped>.html` (themes: `1196,1300`).
  - Convert with `sips -s format jpeg -s formatOptions 80`.
  - Expected: the same layout as the old JPGs, with no German left.
- [ ] **Step 5: Edit the spec.** Delete the sentence "Its labels are German: "Hell" is light, "Dunkel" is dark." from the spec, line 20.
- [ ] **Step 6:** Run `pre-commit run --all-files` and check the images by eye.
- [ ] **Step 7: Commit:** `docs: English screenshots and mockups`. The PR body closes #133.
