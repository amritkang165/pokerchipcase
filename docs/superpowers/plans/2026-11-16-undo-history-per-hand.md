# Undo History per Hand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep `Game.history` to the current hand so the host save stays small over a long tournament (#109).

**Architecture:** One rule in `Game.apply` (PokerCore): a command that raises `state.handNumber` replaces the history with its own undo steps instead of appending them. Nothing in PokerNet, PokerSession or the app changes.

**Tech Stack:** Swift 6, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-16-undo-history-per-hand-design.md`

## Global Constraints

- Swift 6 language mode; no new dependencies.
- No wire change; `TableHost.handoverHistory` stays 50.
- The host still saves before broadcast and ack.
- English in code, comments, docs and commits; Conventional Commits.

## Review Focus

1. A digital `startNextHand` (or `startTournament`) that pays out inside the command because of all-in blinds: the history must hold both the state before the command and the showdown state, so "Change winner" still works. Pinned by `newHandPaidOutAtOnceKeepsTheShowdownStep`.
2. `pauseClock`/`resumeClock`/`transferHost` never start a hand and add no step; unchanged, covered by existing tests.
3. A saved game with a huge history from before this change: shrinks at the next hand start; no test, it follows from the rule.

---

### Task 1: Reset the undo history when a hand starts

**Files:**

- Modify: `Sources/PokerCore/Game.swift` (the `else` branch of `apply(_:by:at:expectedVersion:using:)`, the `history` doc comment)
- Modify: `Tests/PokerCoreTests/UndoTests.swift`, `Tests/PokerCoreTests/AutoShowdownTests.swift`
- Modify: `Tests/PokerCoreTests/WireTests.swift` (`handoverWithFiftyUndoStepsFitsOneMessage`)
- Modify: `README.md` (feature line "Undo for the host")
- Modify: `Sources/PokerNet/PokerNet.docc/Protocol.md` (the `undo` row of the command table)

**Interfaces:**

- Consumes: test helpers `Game.started(_:levels:button:digital:)`, `checkDown()`, `act(_:)`, `rig(_:board:)`, `t0` from `Tests/PokerCoreTests/Helpers.swift`.
- Produces: nothing new; `Game.apply` keeps its signature.

- [ ] **Step 1: Write the failing tests in `Tests/PokerCoreTests/UndoTests.swift`**

```swift
@Test func startTournamentKeepsOnlyTheLastLobbyState() throws {
    var g = Game(hostID: "A", hostName: "A", config: .relaxed)
    try g.apply(.join(player: "B", name: "B"), by: "A", at: t0)
    try g.apply(.join(player: "C", name: "C"), by: "A", at: t0)
    let lobby = g.state
    try g.apply(.startTournament(button: "A"), by: "A", at: t0)
    #expect(g.history == [lobby])
}

@Test func undoReachesOnlyBackToTheEndOfThePreviousHand() throws {
    var g = try Game.started()
    try g.act(.call); try g.act(.call); try g.checkDown()
    try g.apply(.resolveShowdown(winners: [["B"]]), by: "A", at: t0)
    let complete = g.state
    try g.apply(.startNextHand, by: "A", at: t0)
    #expect(g.history.count == 1)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.ignoringVersion == complete.ignoringVersion)
    #expect(throws: Rejection.nothingToUndo) { try g.apply(.undo, by: "A", at: t0) }
}
```

In `Tests/PokerCoreTests/AutoShowdownTests.swift`, next to `allInFromTheBlindsIsPaidInsideTheStartCommand`:

```swift
@Test func newHandPaidOutAtOnceKeepsTheShowdownStep() throws {     // Review Focus 1
    var g = try Game.started(["A": 10, "B": 1000], digital: true)
    #expect(g.history.count == 2 && g.history.last?.phase == .showdown)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "startTournamentKeepsOnlyTheLastLobbyState|undoReachesOnlyBackToTheEndOfThePreviousHand|newHandPaidOutAtOnceKeepsTheShowdownStep"`
Expected: the first two FAIL (history holds every lobby or earlier-hand state); the third FAILS with `history.count == 3` (the join step plus the two steps).

- [ ] **Step 3: Implement the rule in `Game.apply`**

In the `else` branch, replace `history += steps` with: if `next.handNumber > state.handNumber`, `history = steps`, otherwise `history += steps`. One-line comment why: the save holds the history, so it must not grow over a tournament (#109). Update the `history` doc comment to "Earlier states of the current hand, oldest first; a new hand keeps only the state before it."

- [ ] **Step 4: Fix `handoverWithFiftyUndoStepsFitsOneMessage` in `Tests/PokerCoreTests/WireTests.swift`**

It reaches more than 50 steps by playing three hands, which no longer works. Keep the ten-player digital `Game.started(…)` and one `checkDown()` (so the state carries a full board), then set `g.history = Array(repeating: g.state, count: 50)` instead of the loop, `#expect(g.history.count > 50)` and `keepHistory`. Keep the 1 MiB assertion.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: all tests pass. If another test assumed history across hands, it fails here; adapt it only if its intent was not cross-hand undo, otherwise stop and report.

- [ ] **Step 6: Update the docs**

- `README.md`: "Undo for the host" becomes "Undo for the host, within the current hand".
- `Protocol.md`, `undo` row, second column: prepend "Steps back within the current hand; once a hand has started, the previous hand can no longer be undone except the start itself." Keep the existing digital-showdown note.

Run: `pre-commit run --all-files` and the docs build from AGENTS.md.
Expected: both pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/PokerCore/Game.swift Tests/PokerCoreTests/UndoTests.swift Tests/PokerCoreTests/AutoShowdownTests.swift Tests/PokerCoreTests/WireTests.swift README.md Sources/PokerNet/PokerNet.docc/Protocol.md
git commit -m "fix(core): keep the undo history to the current hand

Closes #109."
```

### Manual check (after merge readiness, on the iPhone)

- Debug build with `-debugLongGame`: the console line `debugLongGame: history=… bytes=… save=…` shows a history of one hand and a save time of a few milliseconds.
