# Deferred Issues Batch 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the `deferred` issues #157, #156, #136, #137, #148–#152, #142–#145, #147 and #155 in four PRs.

**Architecture:** There are four PRs:

- PR 1 (`ci`/`test(app)`, branch `chore/ui-test-speed`) holds Tasks 1–2: #157, #156. It goes first, so every later UI test run is faster.
- PR 2 (`fix(net)`, branch `fix/deferred-net-2`) holds Tasks 3–4: #136, #137. It touches no `App/` file and can run in parallel with PR 1.
- PR 3 (`fix(app)`, branch `fix/table-contrast`) holds Tasks 5–8: #148–#152. It starts after PR 1 is merged.
- PR 4 (`fix(app)`, branch `fix/settings-a11y`) holds Tasks 9–11: #142–#145, #147, #155. It starts after PR 3 is merged.

The table PR comes before the Settings PR, against the suggested order. Two of its root causes also cause Settings findings: the translucent `theme.seat` fill is the row background of every form, and the Settings sheet shows the same card glyphs as the table. Fixing them first means PR 4 removes ignore entries instead of chasing the same causes again.

Tasks 2 and 5–11 all edit `App/UITests/KnownAuditIssues.swift`, so they run strictly one after another.

**Tech Stack:** Swift 6, Swift Testing, Network.framework, SwiftUI, XCUITest (`performAccessibilityAudit`), xcodegen 2.47, Xcode 27, GitHub Actions.

**Spec:** the GitHub issues listed below and the owner decisions in this plan.

## Issues in scope

- Tooling: #157 (CI does not compile the UI test target), #156 (UI test run takes about 9.5 minutes).
- Net: #136 (graceful close can leave a connection open on the old host), #137 (undoing a voluntary lobby leave restores a seat no ticket holds).
- Table contrast: #148 (seat plates; its comment adds `seatStack`), #149 (table info texts), #150 (bet preset buttons), #151 (card glyphs and `CardsText`), #152 (showdown hand name and chip deltas).
- Start screen and Settings: #142 (Settings row and segment labels; its comment says the dark schemes show the inverse), #143 (Done), #144 (Dynamic Type in Settings), #145 (clipped text in Settings), #147 (Dynamic Type on the start screen), #155 (Discard contrast).

## Out of scope

- #129 and #153: a separate brainstorm about the table at large text sizes comes later.
- #154: waits until #139 is merged.
- #146: waits with #154 until #139 is merged (owner, 2026-11-18). Its fix (a wrapping name field, Return handled in the field's `onChange`) changes the code the #139 contributor works on. The finding is in "Findings" below for that later fix.
- #139: assigned to an external contributor. Do not touch its scope: the `playerName` cut on read and load in `StartView`, and the host-save load.

## Owner decisions

- Contrast: per finding, the smallest ink or fill change that makes the audit pass (WCAG AA: 4.5:1 normal text, 3:1 large text) and keeps the theme's character. No palette approval step before implementation.
- Each fix removes its ignore entries from `App/UITests/KnownAuditIssues.swift`; the UI test run must then be green.
- The PR body shows before/after screenshots exported from the xcresult, or the agent's judgment of them. The owner decides at merge.
- One root cause is fixed once, in the shared code.
- Dynamic Type (#144–#147): text styles instead of fixed sizes, layout keeps working, the audit is the check. See "Findings" for why #144 and #147 cannot be fixed this way. The owner agreed (2026-11-18): they are closed as not planned with evidence, and their entries stay (Task 11).
- Every PR closes its issues with "Closes #N" in the PR body.

## Findings checked before planning

All measured on 2026-11-18 on `main` at `924b1f2`, simulator `SE3 test`. The probe runs used a scratch worktree with a `print` in `KnownAuditIssues.ignores`; nothing was committed.

- **Run time (#156):** full run 593 s wall, green. Per test: `testPayoutTableSweep` 183 s, `testTurnTableSweep` 150 s, `testStartScreenSweep` 148 s, `testStartScreenWithASavedGame` 17 s, `testNameFieldStopsAt32Characters` 15 s, `testChipCountsUseTheEnglishFormat` 15 s, `testHiddenHoleCardsReadAsHidden` 15 s. Tests sum to 541 s; the rest is build and launch.
- **CI build (#157):** `xcodebuild build` builds the Release configuration and no test bundle. `xcodebuild build-for-testing` with the same flags builds Debug, the app and `PokerChipCaseUITests-Runner.app`; it took 21 s locally and needs no simulator.
- **#142/#143 root cause:** the Settings sheet keeps the color scheme it was opened with. `preferredColorScheme(appearance.colorScheme)` is set only on the window root (`App/Sources/PokerChipCaseApp.swift:35`). An open sheet does not follow it when the Brightness picker changes, but `\.theme` does: `Themed` (`App/Sources/Theme.swift:249-256`) reads the root's scheme and picks the new palette, which flows into the sheet's environment. So the palette (row fill `theme.seat`, tint `theme.formTint`) shows the new brightness while system label colors, the navigation title and the Done button keep the old one.
  - Evidence: the sweep's first pass (Felt Light, opened in the light System scheme) is correct. Every later pass flips brightness inside the open sheet and shows the inverse (`settings-felt-dark`: black labels on near-black; `settings-neon-light`: white on white). Element findings `fourColorDeck`, `backPattern` and `settingsDone` (contrast) occur in exactly those 7 later passes.
  - Probe: adding `.preferredColorScheme(appearance.colorScheme)` to `SettingsView`'s `NavigationStack` removed three of the five no-element contrast findings in the first pass. The two left are the card preview's glyphs (see below).
- **Settings findings left after that fix:** the preview card glyphs `♠` and `♦` (`cardGlyph`, "failed") and the monogram "T" on the red back in the Back color rows ("nearly passed", no identifier). The audit checks these texts even though the preview is `.accessibilityHidden(true)` (`App/Sources/SettingsView.swift:36`), so hiding a text does not exempt it.
- **#145:** the no-element "Text clipped" in Settings is not the segmented Brightness control (it stayed with `.pickerStyle(.menu)`) and not the card preview (it stayed with the preview removed). Candidates left: the monogram letter in the small `CardBackView` icons of the Back color rows (`App/Sources/CardBacks.swift:101-105`, fixed size, `lineLimit(1)`, `minimumScaleFactor(0.4)`), the "♠" at `CardBacks.swift:42`, the "Monogram" picker value, the large title.
- **#144/#147 are not fixed sizes:** every flagged text already uses the default text style ("Four-color deck" `SettingsView.swift:40`, "Back pattern" `:44`, "Back color" `:60`, "Looking for tables…" `StartView.swift:65`, "Nearby tables" `:71`). A screenshot at `UICTContentSizeCategoryAccessibilityXL` shows all of them scaled. The finding depends on position: "Nearby tables" is flagged at y = 442 pt (with a saved game) and not at y = 240 pt (without); "Four-color deck" is flagged at y = 484 and not at y = 240 after scrolling. Elements that a larger size pushes below the visible area are reported. "Done" is a navigation bar button; UIKit caps its size (it uses the Large Content Viewer instead).
  - The `dynamicType`/`discardGame` entry no longer matches anything: the probe reported only contrast for `discardGame`.
- **#146:** with the name "Tester" (what every sweep launches with) there is no finding. With a 32-character name the audit reports "Text clipped" on `playerName` at the default size: 32 characters fill the 303 pt field.
- **#155:** "Discard" uses the destructive role's system red on the light seat fill: "nearly passed" in Felt Light.
- **#148 root cause: translucent seat fill.** `theme.seat` has opacity 0.86–0.95 in all eight palettes (`App/Sources/ThemePalettes.swift:75, 81, 90, 100, 108, 114, 121, 128`). Pixel contrast on the plates is high (cream on near-black 16.8:1), yet the audit fails every scaled seat name. A probe with the same colors made opaque removed all `seatName`, `seatBet` and `seatStack` findings except Neon's acting seat, and reduced `seatCards` and `seatDelta` to the winner seat.
  - **Neon acting seat:** "Tester" and its stack still fail in Neon light and dark. Only Neon gets the glow `shadow` on the acting ring (`App/Sources/RoundTable.swift:128-132`), and that glow lies over the text.
  - **Winner seat:** the winner tint `theme.accent.opacity(0.35)` over the seat (`RoundTable.swift:125`) is translucent and lowers the inks' contrast for real. Composited: Royal light green delta `1e7a3a` 2.96, red `c0392b` 2.99; Felt dark system red 2.64; Royal dark green 3.42. At 0.2 Felt dark red reaches only 4.07.
- **#149 root cause: translucent muted ink.** `muted` is `text.opacity(mutedOpacity)` (`ThemePalettes.swift:66`). The audit fails "Next: 15/30" in Felt dark at a pixel contrast of 5.28 and "Your stack" in Felt light at 4.86, the same pattern as the translucent seat fill.
  - With opaque muted, the light rooms are still tight: full ink on the outer room stop is 3.80 (Felt light), 4.07 (Royal light), 4.51 (Rubin light). Felt dark muted on the inner room stop `14555a` is 4.13.
  - "Pot 170" in the light felts is white on light felt: 2.97 on Felt light's middle stop, 2.90 on Rubin light's inner stop, 3.11 on Royal light's middle stop ("nearly passed").
- **#150:** both preset buttons fail in all 8 passes, although the label is high contrast (14.5:1 in Felt dark). The button has no fill: the label sits on the room gradient inside a `theme.muted` (translucent) capsule border (`App/Sources/ActionBar.swift:30-37`).
- **#152:** `winningHands` ("Flush") fails in the dark Felt, Rubin and Royal passes at a pixel contrast of 8–11:1: the text crosses the gold betting line (`App/Sources/TableSurface.swift:36`, a 0.37 · d circle), which runs through its frame. In the light felts the white text on the light felt fails for real (3.68).
- **#151:** the payout sweep audits the card face stored on the simulator, here `Solid` (the sweeps never set `cardFace`). Its findings:
  - The solid face's big watermark suit, white at opacity 0.28 (`App/Sources/CardViews.swift:119-121, 136`), always fails. It is decoration.
  - White ranks on the solid faces' top stops: blue `4a8be0` 3.47, green `3fb06a` 2.75, red `e0584a` 3.71 (`CardViews.swift:152-158`). Darker tops that reach 4.8 in the same hue: `2470d3`, `2e814e`, `d53524`.
  - The cream and white faces pass on paper: red 4.75, blue 5.32, green 4.69 on `f6efdf`; Neon dark's card inks 5.17 or more.
  - The monogram gold `e8c15a` (`CardBacks.swift:4`) reaches 3.50 on the red back and 3.76 on the green one. That is enough for large text (the 50 pt hole cards pass) but not on the 22 pt icons in Settings.

## Global Constraints

- Swift 6 language mode; no concurrency warnings silenced.
- Code, comments, docs and commits in English; Conventional Commits; every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- No wire format change in this batch, so `Protocol.md` stays as it is.
- Before each PR: `pre-commit run --all-files`, `swift test`, the docs build and the app build from AGENTS.md. PRs that touch `App/` also run the UI test command from AGENTS.md, green.
- `App/project.yml` is the source of project settings; never edit the generated project.
- UI tests stay XCTest; sweeps never pass `-theme` or `-appearance`; every launch passes `-playerName` except `NameFieldTests`.
- Ignore entries only leave `KnownAuditIssues.swift`; never add one without a GitHub issue.
- Diagnosis aid, never committed: to see every finding the audit reports, add this as the first line of `KnownAuditIssues.ignores` in a scratch copy, run the sweep, and grep the output for `AUDIT|`:

  ```swift
  let snap = try? issue.element?.snapshot(); print("AUDIT|\(screen)|\(issue.auditType.rawValue)|\(snap?.identifier ?? "-")|\(snap?.label ?? "-")|\(snap.map { "\($0.frame)" } ?? "-")|\(issue.compactDescription)")
  ```

  A single sweep runs with `-only-testing:PokerChipCaseUITests/<Class>/<test>`; run it without `-quiet`.
- Contrast numbers in this plan are WCAG ratios of opaque sRGB colors. The audit needs some margin above them for small text.
- Tasks marked "inline" take at most three tool calls. The controller does them itself, without a subagent (global CLAUDE.md).

## Process notes

- Review findings that are deferred become GitHub issues labeled `deferred` plus one of `core`, `net`, `protocol`, `app`, `tooling`.
- Each PR body lists the ticked automatic gates (lint, `swift test`, docs, app build; plus the UI test run for PRs that touch `App/`), links this plan, and closes its issues.
- Checks a simulator can show are done by the agent with screenshots and ticked with a note. Only checks a simulator cannot show go to the owner's iPhone as unticked boxes. No PR in this batch has one.
- After every push, check SonarCloud and fix its issues before calling the PR ready.

## Review Focus

1. A nearby table appears or vanishes while the parallel start sweep audits: the audit must not fail on an element that is gone. Handled and commented in Task 2, Step 3.
2. Settings opened in Dark, then switched to System on a light simulator: the sheet must follow to light. Task 9, Step 2 audits the sweep's final System pick.
3. A guest leaves the lobby, then the host starts the tournament, then the guest taps "Rejoin": the rejoin must fail with `gameInProgress` and the ticket must be deleted. Test in Task 4.
4. A slow but live peer during a handover: the close timeout must not cut a 1 MiB message that is still flowing. `closeDeliversWhatWasQueuedBefore` keeps the default timeout (Task 3), and the timeout is 5 s.
5. Two parallel clones host a debug table at the same time, both named "Tester's table": Bonjour renames one, and both tables must still reach their stop. Task 2, Step 4's two green runs pin it; if a table fails to host, pass a distinct `playerName` per table class.

---

## PR 1: UI test speed and CI compile (#157, #156)

### Task 1: CI compiles the UI test target (#157)

**Implementer:** inline.

**Files:**

- Modify: `.github/workflows/ci.yml:87-89` (job `app`)
- Modify: `AGENTS.md` (Commands, App build)

- [ ] **Step 1:** In the `app` job's `run` block, add a third line after the `xcodebuild build` line: `xcodebuild build-for-testing -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet`. Above it, add the comment `# compiles the UI tests without running them (#157)`. Keep `build`: it builds Release, and `build-for-testing` builds Debug. No new action, permission or secret.
- [ ] **Step 2:** Add the same line to the App build block in AGENTS.md, after the `xcodebuild build` line.
- [ ] **Step 3:** Run `pre-commit run --all-files` (actionlint and zizmor), then the three App build commands. Expected: all pass, exit 0. Then rename `waitForTableStop` in one call site only, run the `build-for-testing` line, and expect a compile error. Revert the rename.
- [ ] **Step 4: Commit:** `ci: compile the UI test target in the app build (#157)`

### Task 2: Parallel UI test classes (#156)

**Implementer:** sonnet medium. **Reviewer:** sonnet medium.

**Files:**

- Modify: `App/UITests/SweepTests.swift` (split into three classes)
- Modify: `App/project.yml` (scheme test target)
- Modify: `App/UITests/KnownAuditIssues.swift:56-59`
- Modify: `AGENTS.md` (UI tests command)

**Interfaces:**

- Produces: test classes `StartScreenTests` (`testStartScreenSweep`, `testStartScreenWithASavedGame`), `TurnTableSweepTests` (`testTurnTableSweep`) and `PayoutTableSweepTests` (`testPayoutTableSweep`), all `@MainActor final class … : XCTestCase` with the same `setUp`. The `tableAudit` type set and `openTableSettings(_:)` become file-level `private` in `SweepTests.swift`, shared by the two table classes. Test names stay the same; the screenshots keep their names.

- [ ] **Step 1: Split the classes.** Move the four tests unchanged into the three classes above. No other test change: no theme or brightness combination is dropped.
- [ ] **Step 2: Enable parallel testing.** In `App/project.yml`, the scheme's `test.targets` entry becomes `- name: PokerChipCaseUITests` with `parallelizable: true`. In the AGENTS.md UI test command, add `-maximum-parallel-testing-workers 3` to the `xcodebuild test` line, and add one sentence: "The tests run in parallel on clones of `SE3 test`; the debug tables of one clone show as nearby tables in another."
- [ ] **Step 3: Vanished elements.** In `KnownAuditIssues.ignores`, a failed snapshot is ignored only when the element no longer exists: `guard let snapshot = try? element.snapshot() else { return !element.exists }`. Replace the comment above it with: `// A failed snapshot of an element that is gone (a nearby table from another parallel test that stopped) is ignored; any other failed snapshot is not.`
- [ ] **Step 4: Measure.** Run `xcodegen generate --spec App/project.yml`, then the UI test command from AGENTS.md, under `time`. Expected: green, all 7 tests, 33 screenshots in the export, under 330 s wall (before: 593 s). Run it a second time. Expected: green again. Two runs in a row show that the nearby-table rows do not make the start sweep flaky. Put both times and the before value in the PR body.
- [ ] **Step 5: Commit:** `test(app): run the UI test sweeps in parallel (#156)`. The PR body closes #157 and #156.

---

## PR 2: Net (#136, #137)

### Task 3: Graceful close has a deadline (#136)

**Implementer:** opus high (networking). **Reviewer:** opus high.

**Files:**

- Modify: `Sources/PokerNet/MessageChannel.swift:61-79` (`sendAndClose`, `close`)
- Test: `Tests/PokerNetTests/ChannelTests.swift`, next to `closeDeliversWhatWasQueuedBefore` (line 117)

**Interfaces:**

- Produces: `static let closeTimeout: Duration = .seconds(5)` on `MessageChannel`; `func close(timeout: Duration = MessageChannel.closeTimeout)`; `func sendAndClose(_ data: Data, timeout: Duration = MessageChannel.closeTimeout)`. Both close gracefully as today, and hard-cancel the connection after `timeout` if it is still open.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func closeEndsAgainstAPeerThatStopsReading() async throws {
    // PSK listener that starts each connection but never reads, so the sender's buffers fill up.
    let listener = try NWListener(using: PSK.parameters(code: code4711), on: .any)
    defer { listener.cancel() }
    listener.newConnectionHandler = { $0.start(queue: .global()) }
    let port = try await listener.startAndWaitUntilReady(queue: .global())
    let sender = MessageChannel(to: loopback(port), code: code4711)
    let rec = EventRecorder(sender.events)
    sender.start()
    _ = try await rec.first { $0 == .ready }
    let big = Data(repeating: UInt8(ascii: "a"), count: MessageChannel.maxMessageSize)
    for _ in 0..<64 { sender.send(big) }
    sender.close(timeout: .milliseconds(500))
    #expect(try await rec.waitForEnd(timeout: .seconds(5)) == nil)
}

@Test func closeEndsWhileTheHandshakeStalls() async throws {
    // Plain TCP peer that accepts and never answers the TLS ClientHello.
    let listener = try NWListener(using: .tcp, on: .any)
    defer { listener.cancel() }
    listener.newConnectionHandler = { $0.start(queue: .global()) }
    let port = try await listener.startAndWaitUntilReady(queue: .global())
    let sender = MessageChannel(to: loopback(port), code: code4711)
    let rec = EventRecorder(sender.events)
    sender.start()
    sender.close(timeout: .milliseconds(500))
    _ = try await rec.waitForEnd(timeout: .seconds(5))
}
```

- [ ] **Step 2:** Run `swift test --filter ChannelTests`. Expected: a compile error, because `close(timeout:)` does not exist yet.
- [ ] **Step 3: Implement the deadline.** `close` and `sendAndClose` share one private helper. It does the final send as today (`contentContext: .finalMessage`, `isComplete: true`, cancel in `.contentProcessed`). Then, on `queue`, `asyncAfter` `timeout` cancels the same connection. Capture `connection` when the close is queued; `run(_:)` can replace it later. `cancel()` on a connection that is already cancelled does nothing. Both doc comments end with "…, or after `timeout` at the latest." `TableHost` keeps its calls (`disconnectAll(graceful:)`, `reject`, `finishHandover`); the default timeout covers both scenarios of the issue.
- [ ] **Step 4:** Run `swift test --filter ChannelTests`. Expected: PASS. The two new tests fail on `main` with `TimeoutError`: check this once by setting the timeout to `.seconds(60)`, then revert.
- [ ] **Step 5:** Run `swift test`. Expected: all green, `closeDeliversWhatWasQueuedBefore` and `HostHandoverTests` included.
- [ ] **Step 6: Commit:** `fix(net): hard-close a graceful close that stalls (#136)`

### Task 4: A lobby leave keeps the seat ticket (#137)

**Implementer:** opus high (session and persistence). **Reviewer:** opus high.

**Files:**

- Modify: `Sources/PokerSession/TableSession.swift:199-224` (`leave`)
- Modify: `Sources/PokerNet/TableHost.swift:295` (ponytail comment)
- Test: `Tests/PokerSessionTests/SessionTests.swift:189-210`

- [ ] **Step 1: Write the failing tests, and change one old test**

Add after `guestLeavingTheLobbyFreesTheSeat`:

```swift
@Test func guestLeavingTheLobbyKeepsTicketAndRejoinsAfterUndo() async throws {
    let anna = try await hostSession()
    defer { Task { await anna.leave() } }
    let tickets: SaveFile<SeatTicket> = tempFile()
    let ben = await guestSession(anna, ticketFile: tickets)
    try await eventually { anna.state?.seats.count == 2 && ben.state?.seats.count == 2 }
    let benID = try #require(ben.me)
    #expect(await ben.leave())
    let ticket = try #require(tickets.load())
    try await eventually { anna.state?.seats.count == 1 }
    await anna.send(.undo)
    try await eventually { anna.state?.seats.count == 2 }
    let back = await guestSession(anna, token: ticket.token, ticketFile: tickets)
    defer { Task { await back.leave() } }
    try await eventually { back.connection == .connected }
    #expect(back.me == benID)
    #expect(await anna.tableHost!.snapshot.tokens.count == 2)
}

@Test func lobbyTicketIsDeletedWhenTheGameAlreadyRuns() async throws {
    let anna = try await hostSession()
    defer { Task { await anna.leave() } }
    let tickets: SaveFile<SeatTicket> = tempFile()
    let ben = await guestSession(anna, ticketFile: tickets)
    let cem = await guestSession(anna, name: "Cem")
    defer { Task { await cem.leave() } }
    try await eventually { anna.state?.seats.count == 3 && ben.state?.seats.count == 3 }
    #expect(await ben.leave())
    let ticket = try #require(tickets.load())
    try await eventually { anna.state?.seats.count == 2 }
    await anna.send(.startTournament(button: anna.me!))
    try await eventually { anna.state?.phase == .betting }
    let back = await guestSession(anna, token: ticket.token, ticketFile: tickets)
    defer { Task { await back.leave() } }
    try await eventually { back.connection == .failed(.gameInProgress) }
    #expect(tickets.load() == nil)
}
```

In `leaveDeletesSaveFiles`, Ben now leaves a running game: after the `eventually` line, start the tournament (`await anna.send(.startTournament(button: anna.me!))`, then `try await eventually { ben.state?.phase == .betting }`) before `await ben.leave()`. The rest stays.

- [ ] **Step 2:** Run `swift test --filter SessionTests`. Expected: `guestLeavingTheLobbyKeepsTicketAndRejoinsAfterUndo` FAILS at `#require(tickets.load())`. `lobbyTicketIsDeletedWhenTheGameAlreadyRuns` FAILS at the same line. `leaveDeletesSaveFiles` passes.
- [ ] **Step 3: Keep the ticket after a lobby leave.** In `leave()`, before the lobby branch, set `let leftLobby = !isHost && state?.phase == .lobby && me != nil`. `keepTicket` becomes `leftLobby || connection == .failed(.removed)`. The doc comment's parenthesis becomes "(the ticket stays after `removed` and after leaving the lobby, so the seat can be taken again after an undo by the host or a new join)". On the next join from the start screen, the existing `token` lookup in `JoinSheet`'s closure (`App/Sources/StartView.swift:109`) sends the token, so no app change is needed.
- [ ] **Step 4: Update the #128 comment.** In `TableHost.swift:295`, delete "(also after a voluntary leave)": a lobby leave now rejoins with its token.
- [ ] **Step 5:** Run `swift test` and the docs build. Expected: all green, no DocC warning.
- [ ] **Step 6: Commit:** `fix(session): keep the seat ticket after leaving the lobby (#137)`. The PR body closes #136 and #137 and names the visible effect: after leaving a lobby, the start screen offers "Rejoin `<table>`" until it is used or discarded, as it already does after a removal.

---

## PR 3: Table contrast (#148–#152)

All tasks run the UI tests at their end, after removing their entries. During a task, iterate with a single sweep (`-only-testing:PokerChipCaseUITests/TurnTableSweepTests` or `…/PayoutTableSweepTests`) and the diagnosis aid from Global Constraints. When a candidate below still fails, change the same token in the same direction in small steps. Stop at the first value that passes, and report each final value with its ratio in the PR body.

### Task 5: Opaque seat fill and muted ink (#148, #149)

**Implementer:** sonnet medium. **Reviewer:** sonnet medium.

**Files:**

- Modify: `App/Sources/ThemePalettes.swift:46-71` (shared init), `:73-130` (the eight `seat:` arguments)
- Modify: `App/UITests/KnownAuditIssues.swift:35-41`

**Interfaces:**

- Produces: `private func blend(_ ink: UInt32, over ground: UInt32, _ opacity: Double) -> UInt32` in `ThemePalettes.swift`, per sRGB channel `ink · opacity + ground · (1 − opacity)`, rounded. `Theme.seat` and `Theme.muted` are opaque in every palette; their names and types do not change.

- [ ] **Step 1: Opaque seat fills.** Each palette's `seat:` keeps its color and drops `.opacity(…)`, for example `Color(hex: 0x020806).opacity(0.86)` becomes `Color(hex: 0x020806)`. The probe showed that this alone clears the plates. Comment on the shared init: `// Opaque: the audit fails text on a translucent fill whatever the pixels show (#148).`
- [ ] **Step 2: Opaque muted.** `muted` becomes `Color(hex: blend(textHex, over: room[1], mutedOpacity))`, with the hex values the init already gets. Section headers sit on `room[1]` (`screen`), so they look the same as before.
- [ ] **Step 3: Remove the entries** `seatName`, `seatBet`, `seatStack` (#148) and `nextLevel`, `stackLabel`, `toCall` (#149). Keep `pot` (Task 7). Run both table sweeps.
  - Expected left: Neon's acting seat, the winner seat's `seatCards` and `seatDelta` (Task 6).
  - Possibly also muted texts in some palettes. For each one that still fails, raise that palette's `mutedOpacity` (dark default 0.65, light 0.85, at most 1.0). Where full ink still fails on a light room (expected for Felt light: 3.80 on `36877f`), lighten that palette's outer `room` stop until the text passes. Felt dark's muted on the inner stop is 4.13 today.
- [ ] **Step 4:** Run the full UI test command. Expected: green, with the entries of Task 6 and 7 still in place.
- [ ] **Step 5: Commit:** `fix(app): opaque seat fill and muted ink (#148, #149)`

### Task 6: Seat plate details (#148, #151, #152)

**Implementer:** sonnet medium. **Reviewer:** sonnet medium.

**Files:**

- Modify: `App/Sources/RoundTable.swift:124-138` (`seatLabel` background and overlay)
- Modify: `App/UITests/KnownAuditIssues.swift` (`seatCards`, `seatDelta`)

- [ ] **Step 1: No translucent winner tint.** Delete the winner tint (`RoundTable.swift:124-125`, comment included). A winner and a picked seat keep the 2 pt accent border, and a pick keeps its " ✓". Every tint strength that stays visible fails at least one ink (Royal light green 2.96 at 0.35, Felt dark red 4.07 at 0.2).
- [ ] **Step 2: Glow behind the plate.** The acting ring's glow (Neon only) must not lie over the text. Keep the crisp `strokeBorder` ring in the overlay without a shadow. Draw the glowing copy (same shape, `theme.accent`, `shadow(radius: 4)`, same phase animation) in a `.background` below the opaque seat fill, so only its outside shows.
- [ ] **Step 3:** Remove the entries `seatCards` (#151) and `seatDelta` (#152). Run both table sweeps. Expected: no seat plate finding is left.
- [ ] **Step 4:** Run the full UI test command. Expected: green.
- [ ] **Step 5: Commit:** `fix(app): readable winner and acting seat plates (#148, #151, #152)`

### Task 7: Texts on the felt and the preset buttons (#149, #150, #152)

**Implementer:** sonnet medium. **Reviewer:** sonnet medium.

**Files:**

- Modify: `App/Sources/RoundTable.swift:177-188` (`winnerLines`)
- Modify: `App/Sources/ThemePalettes.swift:73-77, 106-110, 118-123` (`onTable`, `onTableShadow` of the three light felts)
- Modify: `App/Sources/ActionBar.swift:30-37` (preset label)
- Modify: `App/UITests/KnownAuditIssues.swift` (`pot`, `quickPick`, `winningHands`, `winners`)

- [ ] **Step 1: Winner lines on a plate.** `winnerLines` gets the seat plate look: `theme.seatText` ink instead of `theme.onTable`, padding 4/2, an opaque `theme.seat` fill with a `theme.seatBorder` 1 pt border, corner radius 8, and no `onTableShadow`. The lines cross the betting line on every table size, so a plate is the one fix for both the dark felts (line crossing) and the light felts (white on light felt, 3.68).
- [ ] **Step 2: Dark ink on the light felts.** In `feltLight`, `rubyLight` and `royalLight`, `onTable` becomes the palette's `text` ink (`0x062522`, `0x3a1c1c`, `0x14234a`) and `onTableShadow` is dropped (default `false`).
  - Ratios on the felt's inner and middle stops: Felt 8.30/5.37, Royal 7.34/4.94, Rubin 5.22/3.49.
  - If "Pot" still fails in Rubin light, give `pot` the plate from Step 1 in every theme, not in Rubin alone, and say so in the PR body. One look for every theme beats a per-theme exception.
  - `onTable` also draws the bets on the felt and the card slot outlines (`CardViews.swift:173`); check them in the turn screenshots.
- [ ] **Step 3: Preset buttons with a fill.** The preset label gets an opaque `theme.seat` capsule fill under the border and `theme.seatText` ink. The border becomes `theme.seatBorder`. The probe showed that the plates pass once their fill is opaque; the label alone on the room gradient fails at 14.5:1.
- [ ] **Step 4:** Remove the entries `pot` (#149), `quickPick` (#150), `winningHands` and `winners` (#152). Run both table sweeps. Expected: only `cardGlyph` is left (Task 8).
- [ ] **Step 5:** Run the full UI test command. Expected: green.
- [ ] **Step 6: Commit:** `fix(app): readable pot, winner lines and bet presets (#149, #150, #152)`

### Task 8: Card glyphs (#151)

**Implementer:** sonnet medium. **Reviewer:** sonnet medium.

**Files:**

- Modify: `App/Sources/CardViews.swift:126-163` (`indexed`, `solidFill`)
- Modify: `App/Sources/CardBacks.swift:96-105` (monogram)
- Modify: `App/UITests/KnownAuditIssues.swift` (`cardGlyph`)

- [ ] **Step 1: Decoration drawn, not text.** The solid face's watermark suit (`bigOpacity < 1`) and the monogram letter on a card back are drawn with `Canvas` (`GraphicsContext.draw(_:at:anchor:)` of the same `Text`, same font, size, opacity, color and position). A `Canvas` adds no text element, and hiding a text from accessibility does not exempt it from the audit (see Findings). Comment: `// Drawn, not a Text: decoration, which the contrast audit would judge as text (#151).` Ranks and the faces' other suits stay `Text`: they carry the card and must pass.
- [ ] **Step 2: Darker solid tops.** In `solidFill`, the top stops become blue `0x2470d3`, green `0x2e814e`, red `0xd53524`, so white ranks reach 4.8. Spades stay.
- [ ] **Step 3:** Remove both `cardGlyph` entries and run the payout sweep. Expected: no finding. Then run the payout sweep once more with `-cardFace classic` added to its launch arguments in a scratch copy, not committed. Expected: no finding. Then `-cardFace centered` and `-cardFace jumbo`. If a cream-card ink fails, darken that ink (`ThemePalettes.swift:24-27`) the same way and add its ratio to the PR body.
- [ ] **Step 4:** Run the full UI test command. Expected: green. Export the screenshots.
- [ ] **Step 5: Commit:** `fix(app): readable card glyphs (#151)`. The PR body closes #148–#152 and shows before/after screenshots of `table-turn` and `table-payout` for all eight passes (before: from `main`), with the agent's judgment of each look change: opaque plates, no winner tint, plated winner lines, filled presets, dark pot ink on light felts, darker solid faces.

---

## PR 4: Start screen and Settings (#142–#145, #147, #155)

### Task 9: The Settings sheet follows the brightness (#142, #143)

**Implementer:** sonnet medium. **Reviewer:** sonnet medium.

**Files:**

- Modify: `App/Sources/SettingsView.swift:15-69`
- Modify: `App/UITests/ThemeSweep.swift:24-26`
- Modify: `App/UITests/KnownAuditIssues.swift:17-20`

- [ ] **Step 1: Fix the root cause.** Add `.preferredColorScheme(appearance.colorScheme)` after the `NavigationStack` in `SettingsView`; the view already reads `appearance`. Comment: `// A sheet keeps the scheme it opened with; the root's preferredColorScheme does not reach it while it is open (#142).`
- [ ] **Step 2: Audit the last pick.** In `sweepThemes`, when `auditsSettings` is true, audit `settings` once more after the final `pick(theme: "Felt", brightness: "System", …)`, before `closeSettings`. No screenshot. This pins Review Focus 2.
- [ ] **Step 3:** Remove the entries `fourColorDeck`, `backPattern`, the no-element `settings` contrast (#142) and `settingsDone` contrast (#143). Run `StartScreenTests`. Expected: no contrast finding in Settings in any pass. The preview glyphs and the monogram were fixed in Task 8; if a no-element contrast finding remains, find it with the diagnosis aid and fix its ink the same way.
- [ ] **Step 4:** Run the full UI test command. Expected: green. In the `settings-*` screenshots, labels, title and Done follow each pass's brightness.
- [ ] **Step 5: Commit:** `fix(app): Settings sheet follows the brightness it sets (#142, #143)`

### Task 10: Clipped Settings text and the Discard red (#145, #155)

**Implementer:** sonnet medium. **Reviewer:** sonnet medium.

**Files:**

- Modify: `App/Sources/StartView.swift:51`, `:55` (Discard). Do not touch the name field or its `onChange` (#139, #146, #154).
- Modify: the element behind #145, found in Step 1
- Modify: `App/UITests/KnownAuditIssues.swift` (the Settings `textClipped` entry, `discardGame` entries). The `playerName` `textClipped` entry (#146) stays.

- [ ] **Step 1: Find #145.** Remove the no-element `textClipped`/`settings` entry and run `StartScreenTests/testStartScreenSweep`. If it still fails, bisect the candidates from Findings in a scratch copy, one per run, by removing the candidate: the back icons' monogram (if Task 8's `Canvas` did not already clear it), the "♠" at `CardBacks.swift:42`, the Back pattern picker. Then fix that element: a decorative card glyph gets the `Canvas` from Task 8; a label gets `lineLimit(nil)` or wraps. Report the element in the PR body.
- [ ] **Step 2: Discard in the theme's red.** Both Discard buttons get `.foregroundStyle(theme.red)`: `c0392b` on light seats, the system red on dark ones. Remove the `discardGame` contrast entry (#155) and the stale `discardGame` `dynamicType` entry (Findings).
- [ ] **Step 3:** Run the full UI test command. Expected: green.
- [ ] **Step 4: Commit:** `fix(app): theme red for Discard, unclipped Settings text (#145, #155)`

### Task 11: Dynamic Type findings that are audit artifacts (#144, #147)

**Implementer:** inline (main session).

**Files:**

- Modify: `App/UITests/KnownAuditIssues.swift` (`dynamicType` entries)

- [ ] **Step 1: Regroup the entries.** The `dynamicType` entries for `settingsDone`, `fourColorDeck`, `backPattern`, `backColorHeader` (#144) and `nearbyHeader`, `nearbyTable`, `nearbySearching` (#147) move under one comment: `// Not app-fixable: these texts use text styles and scale; the audit reports elements that a larger size pushes off screen, and the navigation bar caps Done (Large Content Viewer). Evidence in #144 and #147.` Delete the comment above `nearbySearching` that this one replaces.
- [ ] **Step 2: Attach the evidence.** Take a screenshot at `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXL`, of the start screen with a saved game and of Settings scrolled down. Close #144 and #147 as not planned, with this comment: "These texts already use text styles and scale (screenshots). The audit flags them only where a larger size pushes them off screen: "Nearby tables" fails at y 442 pt and passes at y 240 pt. "Done" is a navigation bar item, which UIKit caps. The entries stay with this reason."
- [ ] **Step 3:** Run the full UI test command. Expected: green. The PR body closes #142, #143, #145 and #155, names #144 and #147 as closed not planned (owner approved) with the link to the evidence, and shows before/after `settings-*` and `start-saved-game` screenshots.
- [ ] **Step 4: Commit:** `test(app): document the Dynamic Type audit artifacts (#144, #147)`
