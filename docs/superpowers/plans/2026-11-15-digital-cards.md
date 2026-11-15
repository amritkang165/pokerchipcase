# Digital Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An optional per-table mode in which the app deals the cards, shows each player only their own hole cards, and pays out the showdown by itself.

**Architecture:** Cards live in `GameState` (`Seat.holeCards`, `board`, `deck`). `PokerCore` deals with an injected random number generator, ranks hands with a brute-force evaluator, and pays out inside `Game.apply`, leaving the showdown state as its own undo step. `TableHost` sends every client `state.redacted(for:)`, so the deck and other players' cards never leave the host. The app draws the board, the peek-to-see hole cards and the revealed hands from that state.

**Tech Stack:** Swift 6 language mode, Swift Testing, Network.framework, SwiftUI. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-15-digital-cards-design.md`

## Global Constraints

- Swift 6 language mode stays; fix concurrency errors instead of silencing them.
- Code, comments, docs and commits in English. Commits follow Conventional Commits with an optional scope.
- No new dependencies.
- With `digitalCards == false` nothing changes: `holeCards`, `board` and `deck` stay empty and every existing test passes unmodified, apart from the `"v":1` → `"v":2` strings.
- Protocol version is 2. `Sources/PokerNet/PokerNet.docc/Protocol.md` changes in the same PR as the wire format.
- Every new `public` symbol has a doc comment; the DocC build runs with `--warnings-as-errors`.
- A `ponytail:` comment marks each deliberate simplification and names its ceiling and upgrade path.
- Branches: `feat/digital-cards-core` from `feat/round-table` (Tasks 1–6, PR 1), `feat/digital-cards-app` from `feat/digital-cards-core` (Tasks 7–10, PR 2). A PR targets `main` if its base branch is already merged there, otherwise the branch it was created from.
- Gates before each PR, from the repo root: `pre-commit run --all-files`, `swift test`, the DocC build and the app build from `AGENTS.md`.

## Review Focus

Inputs the spec implies but does not list as tests. Each has a test in the task named.

1. Blinds put a player all-in when the hand starts (heads-up, small blind ≥ stack): the hand reaches showdown inside `startTournament` or `startNextHand`. Expected: 5 board cards, automatic payout, undo returns to that showdown. (Task 4)
2. The host removes a player who holds cards mid-hand. Expected: that hand is never revealed and never sent to anyone but its owner, also at showdown. (Task 5)
3. A player busts and stays connected. Expected: the seat holds no cards in later hands; cards of the bust hand do not linger. (Task 4)
4. Undo in the middle of a hand. Expected: hole cards, board and deck are the same as before the undone command; nothing is re-dealt. (Task 3)
5. "Change winner", then a second undo, then the hand is played to showdown again. Expected: the second undo returns to betting with the same cards, and the new showdown pays out automatically again. (Task 4)

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/PokerCore/Card.swift` (new) | `Card`, its string form and Codable, the full deck |
| `Sources/PokerCore/HandValue.swift` (new) | `HandValue`, `evaluate(_:)` |
| `Sources/PokerCore/DigitalCards.swift` (new) | State logic of the mode: drawing, reveal rule, showdown winners, redaction |
| `Sources/PokerCore/Types.swift` | New fields on `TournamentConfig`, `Seat`, `GameState` |
| `Sources/PokerCore/Hand.swift` | Dealing in `startHand`, `endRound`, `enterShowdown` |
| `Sources/PokerCore/Game.swift` | Generator parameter, automatic payout |
| `Sources/PokerCore/Wire.swift` | `Wire.version = 2` |
| `Sources/PokerSession/Display.swift` | `dealerHint` is nil in digital games |
| `Sources/PokerNet/TableHost.swift` | Redacted broadcast |
| `App/Sources/CardViews.swift` (new) | Card face, card back, empty slot, hole cards with peek, `CardBack` setting |
| `App/Sources/Theme.swift`, `SettingsView.swift` | Task 7 |
| `App/Sources/StartView.swift`, `LobbyView.swift`, `HostMenu.swift`, `DebugBots.swift` | Task 8 |
| `App/Sources/RoundTable.swift`, `TableView.swift`, `RankingView.swift` | Task 9 |

---

### Task 1: Card

**Files:**
- Create: `Sources/PokerCore/Card.swift`
- Create: `Tests/PokerCoreTests/CardTests.swift`
- Modify: `Tests/PokerCoreTests/Helpers.swift`
- Modify: `Sources/PokerCore/PokerCore.docc/PokerCore.md` (new topic group `### Cards` with ``Card``)

**Interfaces:**
- Produces:
  - `public struct Card: Hashable, Codable, Sendable, CustomStringConvertible` with `public let rank: Int` (2…14) and `public let suit: Suit`
  - `public enum Card.Suit: String, CaseIterable, Sendable` with cases `clubs = "c"`, `diamonds = "d"`, `hearts = "h"`, `spades = "s"`
  - `public init?(_ text: String)`: exactly two characters, rank from `23456789TJQKA`, then the suit's raw value; anything else is nil
  - `public var description: String`: the same two characters, e.g. `"Ah"`
  - `public static let fullDeck: [Card]`: all 52, clubs to spades, each 2 to ace
  - Codable: a single string value; decoding a string that `init?(_:)` refuses throws `DecodingError.dataCorrupted`
  - Test helper in `Helpers.swift`: `func cards(_ text: String) -> [Card]` splits on spaces and force-unwraps `Card($0)`

- [ ] **Step 1: Create the branch and commit spec and plan**

```bash
git switch -c feat/digital-cards-core feat/round-table
git add docs/superpowers/specs/2026-11-15-digital-cards-design.md docs/superpowers/plans/2026-11-15-digital-cards.md
git commit -m "docs: spec and plan for digital cards"
```

- [ ] **Step 2: Write the failing tests** in `CardTests.swift`

```swift
@Test func cardStringRoundTrips() throws {
    #expect(Card("Ah") == Card(rank: 14, suit: .hearts))   // memberwise init is internal
    #expect(Card("Tc")?.rank == 10 && Card("2s")?.suit == .spades)
    #expect(Card("Ah")?.description == "Ah")
    let data = try Wire.encoder.encode(cards("Ah Tc 2s"))
    #expect(String(decoding: data, as: UTF8.self) == #"["Ah","Tc","2s"]"#)
    #expect(try Wire.decoder.decode([Card].self, from: data) == cards("Ah Tc 2s"))
}

@Test func invalidCardStringsAreRefused() {
    for text in ["1x", "A", "Ahh", "ah", "AH", ""] { #expect(Card(text) == nil, "\(text)") }
    #expect(throws: DecodingError.self) { try Wire.decoder.decode([Card].self, from: Data(#"["1x"]"#.utf8)) }
}

@Test func fullDeckHas52DistinctCards() {
    #expect(Card.fullDeck.count == 52 && Set(Card.fullDeck).count == 52)
}
```

- [ ] **Step 3: Run** `swift test --filter CardTests`. Expected: FAIL to compile, `Card` is not defined.
- [ ] **Step 4: Implement `Card`** as specified under Interfaces, add `cards(_:)` to `Helpers.swift`, add the DocC topic group.
- [ ] **Step 5: Run** `swift test --filter CardTests`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(core): card type with a two-character wire form`

---

### Task 2: Hand evaluator

**Files:**
- Create: `Sources/PokerCore/HandValue.swift`
- Create: `Tests/PokerCoreTests/EvaluatorTests.swift`
- Modify: `Sources/PokerCore/PokerCore.docc/PokerCore.md` (add ``HandValue`` and ``evaluate(_:)`` to `### Cards`)

**Interfaces:**
- Consumes: `Card`, `cards(_:)` from Task 1.
- Produces:
  - `public struct HandValue: Comparable, Sendable` with `public let category: Category` and `public let ranks: [Int]`
  - `public enum HandValue.Category: Int, Comparable, CaseIterable, Sendable`, in this order: `highCard, pair, twoPair, threeOfAKind, straight, flush, fullHouse, fourOfAKind, straightFlush`
  - `ranks`: for straights and straight flushes only the top rank (`[5]` for the wheel). Otherwise the distinct ranks ordered by how often they occur, then by rank, both descending: a full house of sevens over aces is `[7, 14]`, a pair of aces with K 9 7 is `[14, 13, 9, 7]`.
  - `<` compares `category`, then `ranks` lexicographically. `==` is synthesized, so equal hands in different suits are equal.
  - `public var name: String`: "High card", "Pair", "Two pair", "Three of a kind", "Straight", "Flush", "Full house", "Four of a kind", "Straight flush"; "Royal flush" for a straight flush with `ranks == [14]`
  - `public func evaluate(_ cards: [Card]) -> HandValue`: 5 to 7 cards (`precondition`), the maximum over every 5-card combination

- [ ] **Step 1: Write the failing tests**

```swift
private func value(_ text: String) -> HandValue { evaluate(cards(text)) }

@Test func categoriesRankInOrder() {
    let hands = [
        "Ah Kd 9c 7s 3h", "Ah Ad 9c 7s 3h", "Ah Ad 9c 9s 3h", "Ah Ad Ac 7s 3h", "5h 6d 7c 8s 9h",
        "Ah Jh 9h 7h 3h", "Ah Ad Ac 7s 7h", "Ah Ad Ac As 3h", "5h 6h 7h 8h 9h",
    ].map(value)
    #expect(hands.map(\.category) == HandValue.Category.allCases)
    for (lower, higher) in zip(hands, hands.dropFirst()) { #expect(lower < higher) }
}

@Test func kickersDecideWithinACategory() {
    #expect(value("Ah Ad Kc 7s 3h") > value("As Ac Qc 7d 3d"))          // pair: kicker
    #expect(value("Kh Kd 2c 3s 4h") > value("Qh Qd Ac Ks Jh"))          // pair rank before kicker
    #expect(value("Ah Ad 9c 9s Kh") > value("As Ac 9d 9h Qh"))          // two pair: kicker
    #expect(value("3h 3d 3c 2s 2h") > value("2d 2c 2h As Ah"))          // full house: trips first
    #expect(value("Ah Jh 9h 7h 3h") > value("Kd Qd Jd 9d 7d"))          // flush: highest card
    #expect(value("Ah Kd 9c 7s 3h") == value("As Kc 9d 7h 3d"))         // suits never break ties
}

@Test func aceIsLowOnlyInTheWheel() {
    let wheel = value("Ah 2d 3c 4s 5h")
    #expect(wheel.category == .straight && wheel.ranks == [5])
    #expect(wheel < value("2d 3c 4s 5h 6d"))
    #expect(value("Qh Kd Ac 2s 3h").category == .highCard)              // no wrap-around
}

@Test func bestFiveOfSevenIsFound() {
    let royal = value("Ah Kh 2c 3d Qh Jh Th")
    #expect(royal.category == .straightFlush && royal.name == "Royal flush")
    #expect(value("Ah Ad 7c 7d 7h 2s 2c") == value("7c 7d 7h Ah Ad"))
    #expect(value("9h 8h 7h 6h 5h").name == "Straight flush")
}

@Test func boardThatPlaysTies() {
    let board = "Ah Kh Qh Jh Th"
    #expect(evaluate(cards("2c 3d " + board)) == evaluate(cards("9s 9d " + board)))
}
```

- [ ] **Step 2: Run** `swift test --filter EvaluatorTests`. Expected: FAIL to compile.
- [ ] **Step 3: Implement `HandValue` and `evaluate(_:)`.** Rank one 5-card hand, then take the maximum over all 5-card index combinations of the input. Mark the brute force with `// ponytail: checks all 21 five-card hands of 7 cards; a lookup-table evaluator if this ever shows in a profile`.
- [ ] **Step 4: Run** `swift test --filter EvaluatorTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): hand evaluator for 5 to 7 cards`

---

### Task 3: Dealing

**Files:**
- Modify: `Sources/PokerCore/Types.swift`, `Sources/PokerCore/Hand.swift`, `Sources/PokerCore/Game.swift`, `Sources/PokerSession/Display.swift`
- Create: `Sources/PokerCore/DigitalCards.swift`
- Create: `Tests/PokerCoreTests/DealingTests.swift`
- Modify: `Tests/PokerCoreTests/Helpers.swift`, `Tests/PokerCoreTests/ChipConservationTests.swift`, `Tests/PokerSessionTests/DisplayTests.swift`

**Interfaces:**
- Consumes: `Card.fullDeck`.
- Produces:
  - `public var digitalCards: Bool` on `TournamentConfig`; `init(startingStack:levels:digitalCards: Bool = false)`
  - `Seat.holeCards: [Card] = []`, `GameState.board: [Card] = []`, `GameState.deck: [Card] = []`, all `public var`
  - `Game.apply(_:by:at:expectedVersion:)` keeps its signature and forwards to the new `public mutating func apply<R: RandomNumberGenerator>(_ command: Command, by actor: PlayerID, at now: Date, expectedVersion: Int? = nil, using rng: inout R) throws(Rejection)` with a `SystemRandomNumberGenerator`
  - Internal: `GameState.apply(_:by:at:using:)`, `startHand(using:)`, `startNextHand(using:)` take the generator; in `DigitalCards.swift`, `mutating func draw(_ count: Int) -> [Card]` removes and returns the first `count` cards of `deck`
  - Dealing, only when `config.digitalCards`: `startHand` sets `deck = Card.fullDeck.shuffled(using: &rng)`, `board = []`, and gives each seat in seat order `draw(2)`, eliminated seats `[]`; `endRound` appends `draw(3)` to `board` on the move to the flop and `draw(1)` on the moves to turn and river; `enterShowdown` first appends `draw(5 - board.count)`
  - `GameState.dealerHint` returns nil when `config.digitalCards`
  - Test helpers: `SeededRNG` moves from `ChipConservationTests.swift` to `Helpers.swift` and loses `private`; `Game.started(...)` gains `digital: Bool = false`; `mutating func rig(_ holes: KeyValuePairs<PlayerID, String>, board: String)` on `Game` sets those seats' `holeCards` and `state.deck = cards(board)` (call it right after `started`, before any action)

- [ ] **Step 1: Write the failing tests** in `DealingTests.swift`

```swift
private func allCards(_ s: GameState) -> [Card] { s.seats.flatMap(\.holeCards) + s.board + s.deck }

@Test func realCardGamesHoldNoCards() throws {
    var g = try Game.started()
    try g.act(.call); try g.act(.call); try g.checkDown()
    #expect(allCards(g.state).isEmpty && g.state.phase == .showdown)
}

@Test func everySeatGetsTwoCardsAndTheBoardGrowsByStreet() throws {
    var g = try Game.started(digital: true)
    #expect(g.state.seats.allSatisfy { $0.holeCards.count == 2 } && g.state.board.isEmpty)
    try g.act(.call); try g.act(.call); try g.act(.check)
    #expect(g.state.street == .flop && g.state.board.count == 3)
    try g.act(.check); try g.act(.check); try g.act(.check)
    #expect(g.state.street == .turn && g.state.board.count == 4)
    try g.act(.check); try g.act(.check); try g.act(.check)
    #expect(g.state.street == .river && g.state.board.count == 5)
    #expect(allCards(g.state).count == 52 && Set(allCards(g.state)).count == 52)
}

@Test func sameSeedDealsTheSameCards() throws {
    func deal(seed: UInt64) throws -> GameState {
        var rng = SeededRNG(state: seed)
        var g = Game(hostID: "A", hostName: "A",
                     config: TournamentConfig(startingStack: 1000, levels: tenTwenty, digitalCards: true))
        try g.apply(.join(player: "B", name: "B"), by: "A", at: t0)
        try g.apply(.startTournament(button: "A"), by: "A", at: t0, using: &rng)
        return g.state
    }
    #expect(try deal(seed: 1) == deal(seed: 1))
    #expect(try deal(seed: 1).seats.map(\.holeCards) != deal(seed: 2).seats.map(\.holeCards))
}

@Test func undoMidHandKeepsTheCards() throws {       // Review Focus 4
    var g = try Game.started(digital: true)
    try g.act(.call); try g.act(.call)
    let before = g.state
    try g.act(.check)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.seats.map(\.holeCards) == before.seats.map(\.holeCards))
    #expect(g.state.board == before.board && g.state.deck == before.deck)
}
```

Add to `DisplayTests.swift`:

```swift
@Test func noDealerHintWithDigitalCards() throws {
    var g = try started()
    #expect(g.state.dealerHint == .dealHand)
    g.state.config.digitalCards = true
    #expect(g.state.dealerHint == nil)
}
```

- [ ] **Step 2: Run** `swift test --filter "DealingTests|DisplayTests"`. Expected: FAIL to compile.
- [ ] **Step 3: Implement** the fields, the generator threading, `draw(_:)`, the dealing and the `dealerHint` guard as listed under Interfaces. A digital game that reaches showdown still waits for `resolveShowdown` after this task; Task 4 adds the payout. Put this comment at `draw(_:)`: `// The deck cannot run out: a hand uses at most 10 × 2 + 5 = 25 of 52 cards.`
- [ ] **Step 4: Run** `swift test`. Expected: PASS, including every existing test.
- [ ] **Step 5: Commit** `feat(core): deal hole cards and the board in digital games`

---

### Task 4: Automatic payout and the reveal rule

**Files:**
- Modify: `Sources/PokerCore/DigitalCards.swift`, `Sources/PokerCore/Game.swift`
- Create: `Tests/PokerCoreTests/AutoShowdownTests.swift`
- Modify: `Tests/PokerCoreTests/ChipConservationTests.swift`

**Interfaces:**
- Consumes: `evaluate(_:)`, `rig(_:board:)`, `Game.started(digital:)`, the existing `resolveShowdown(_:)` and `split(...)`.
- Produces, in `DigitalCards.swift`:
  - `public func isRevealed(_ seat: Seat) -> Bool` on `GameState`: phase is `showdown`, `handComplete` or `finished`, the seat has not folded, and at least 2 seats have not folded
  - `public func handValue(of seat: Seat) -> HandValue?` on `GameState`: `evaluate(seat.holeCards + board)`, nil unless the seat holds 2 cards and the board 5
  - `func showdownWinners() -> [[PlayerID]]` on `GameState` (internal): per pot, the `eligible` players whose `handValue` equals the pot's maximum, in `eligible` order
- Produces, in the generic `Game.apply`: after the command is applied and the old state appended to `history`, if `next.config.digitalCards`, the old phase was not `showdown` and the new phase is, then append `next` to `history` and call `next.resolveShowdown(next.showdownWinners())`. Update the doc comment of `Command.undo`: in a digital game the first undo after a showdown returns to the showdown before the payout.

- [ ] **Step 1: Write the failing tests** in `AutoShowdownTests.swift`

```swift
private let rags = "3s 8d Jc 4h 9s"

@Test func bestHandIsPaidAtOnce() throws {
    var g = try Game.started(digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd", "C": "7c 2d"], board: rags)
    try g.act(.call); try g.act(.call); try g.checkDown()
    #expect(g.state.phase == .handComplete && g.state.board == cards(rags))
    #expect(g.state.seats.map(\.stack) == [1040, 980, 980])
    #expect(g.state.seats.allSatisfy(g.state.isRevealed))
    #expect(g.state.handValue(of: g.state.seats[0])?.name == "Pair")
}

@Test func sidePotGoesToTheBestEligibleHand() throws {
    var g = try Game.started(["A": 1000, "B": 300, "C": 1000], digital: true)
    g.rig(["A": "7c 2d", "B": "Ah Ad", "C": "Kh Kd"], board: rags)
    try g.act(.allIn); try g.act(.call); try g.act(.call)
    #expect(g.state.seat("B")?.stack == 900 && g.state.seat("C")?.stack == 1400)
    #expect(g.state.seat("A")?.eliminatedRank == 3 && g.state.board.count == 5)
}

@Test func tiedHandsSplitAndFoldedHandsDoNotCount() throws {
    var g = try Game.started(levels: [BlindLevel(smallBlind: 5, bigBlind: 10, duration: 600)], digital: true)
    g.rig(["A": "Ah 2c", "B": "7c 7d", "C": "Ad 2s"], board: "Kh Qd Jc 9s 4h")
    try g.act(.call); try g.act(.fold); try g.checkDown()
    #expect(g.state.seat("A")?.stack == 1002 && g.state.seat("C")?.stack == 1003)
    #expect(!g.state.isRevealed(g.state.seat("B")!))
}

@Test func foldWinRevealsNothing() throws {
    var g = try Game.started(digital: true)
    try g.act(.fold); try g.act(.fold)
    #expect(g.state.phase == .handComplete && !g.state.seats.contains(where: g.state.isRevealed))
}

@Test func undoAfterThePayoutReturnsToTheShowdown() throws {
    var g = try Game.started(digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd", "C": "7c 2d"], board: rags)
    try g.act(.call); try g.act(.call); try g.checkDown()
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.phase == .showdown && g.state.pots == [Pot(amount: 60, eligible: ["A", "B", "C"])])
    #expect(g.state.seats.allSatisfy(g.state.isRevealed))
    try g.apply(.resolveShowdown(winners: [["C"]]), by: "A", at: t0)
    #expect(g.state.phase == .handComplete && g.state.seat("C")?.stack == 1040)
}

@Test func secondUndoReturnsToBettingAndTheHandPaysOutAgain() throws {   // Review Focus 5
    var g = try Game.started(digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd", "C": "7c 2d"], board: rags)
    try g.act(.call); try g.act(.call); try g.checkDown()
    try g.apply(.undo, by: "A", at: t0); try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.phase == .betting && g.state.street == .river && g.state.board == cards(rags))
    try g.checkDown()
    #expect(g.state.phase == .handComplete && g.state.seat("A")?.stack == 1040)
}

@Test func payoutThatEndsTheTournamentCanBeUndone() throws {
    var g = try Game.started(["A": 1000, "B": 1000], digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd"], board: rags)
    try g.act(.allIn); try g.act(.call)
    #expect(g.state.phase == .finished && g.state.seat("A")?.stack == 2000)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.phase == .showdown)
}

@Test func bustedSeatHoldsNoCardsInLaterHands() throws {              // Review Focus 3
    var g = try Game.started(digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd", "C": "7c 2d"], board: rags)
    try g.act(.allIn); try g.act(.call); try g.act(.fold)
    try g.apply(.startNextHand, by: "A", at: t0)
    #expect(g.state.seat("B")?.isEliminated == true && g.state.seat("B")?.holeCards == [])
    #expect(g.state.seat("A")?.holeCards.count == 2 && g.state.seat("C")?.holeCards.count == 2)
}

@Test func allInFromTheBlindsIsPaidInsideTheStartCommand() throws {     // Review Focus 1
    var g = try Game.started(["A": 10, "B": 1000], digital: true)
    #expect(g.state.phase == .handComplete || g.state.phase == .finished)
    #expect(g.state.board.count == 5 && g.state.seats.map(\.stack).reduce(0, +) == 1010)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.phase == .showdown && g.state.pots == [Pot(amount: 20, eligible: ["A", "B"])])
}
```

In `ChipConservationTests.swift`, turn `chipsAreConservedInRandomTournaments` into `@Test(arguments: [false, true]) func chipsAreConservedInRandomTournaments(digital: Bool)`, pass `digitalCards: digital` to the config, and apply `startTournament`, every `act` and `startNextHand` through `g.apply(…, using: &rng)` instead of the helpers, so a failing seed deals the same cards again. The `.showdown` case stays for the real-card run.

- [ ] **Step 2: Run** `swift test --filter "AutoShowdownTests|ChipConservationTests"`. Expected: FAIL to compile.
- [ ] **Step 3: Implement** `isRevealed`, `handValue(of:)`, `showdownWinners()` and the payout in `Game.apply`.
- [ ] **Step 4: Run** `swift test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): pay out the showdown automatically in digital games`

---

### Task 5: Redaction

**Files:**
- Modify: `Sources/PokerCore/DigitalCards.swift`
- Create: `Tests/PokerCoreTests/RedactionTests.swift`

**Interfaces:**
- Consumes: `isRevealed(_:)`.
- Produces: `public func redacted(for viewer: PlayerID?) -> GameState` on `GameState`: `deck = []`; `holeCards = []` on every seat that is neither the viewer's nor revealed. Nothing else changes.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func otherHandsAndTheDeckAreHidden() throws {
    let g = try Game.started(digital: true)
    var expected = g.state
    expected.deck = []
    expected.seats[0].holeCards = []
    expected.seats[2].holeCards = []
    #expect(g.state.redacted(for: "B") == expected)
    #expect(expected.seats[1].holeCards.count == 2)
    #expect(g.state.redacted(for: nil).seats.allSatisfy { $0.holeCards.isEmpty })
    #expect(g.state.redacted(for: "nobody").seats.allSatisfy { $0.holeCards.isEmpty })
}

@Test func revealedHandsStayAndFoldedOnesDoNot() throws {
    var g = try Game.started(digital: true)
    try g.act(.call); try g.act(.fold); try g.checkDown()             // B folded; A and C show down
    let full = g.state
    for viewer in ["A", "B", "C", nil] as [PlayerID?] {
        let seen = full.redacted(for: viewer)
        #expect(seen.deck.isEmpty && seen.board == full.board)
        #expect(seen.seat("A")?.holeCards == full.seat("A")?.holeCards)
        #expect(seen.seat("C")?.holeCards == full.seat("C")?.holeCards)
        #expect(seen.seat("B")?.holeCards == (viewer == "B" ? full.seat("B")!.holeCards : []))
    }
}

@Test func removedPlayerIsNeverRevealed() throws {                    // Review Focus 2
    var g = try Game.started(["A": 1000, "B": 1000, "C": 1000, "D": 1000], digital: true)
    try g.apply(.removePlayer(player: "C"), by: "A", at: t0)
    try g.checkDown()
    #expect(g.state.phase == .handComplete && !g.state.isRevealed(g.state.seat("C")!))
    #expect(g.state.redacted(for: "A").seat("C")?.holeCards == [])
}
```

- [ ] **Step 2: Run** `swift test --filter RedactionTests`. Expected: FAIL to compile.
- [ ] **Step 3: Implement `redacted(for:)`.**
- [ ] **Step 4: Run** `swift test --filter RedactionTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): redact the state for one viewer`

---

### Task 6: Per-player broadcast, protocol version 2, PR 1

**Files:**
- Modify: `Sources/PokerNet/TableHost.swift` (`broadcastState`), `Sources/PokerCore/Wire.swift` (`version`, the `{"v": 1, …}` doc comment)
- Modify: `Sources/PokerNet/PokerNet.docc/Protocol.md`
- Modify: `Tests/PokerCoreTests/WireTests.swift`, `Tests/PokerNetTests/HostCommandTests.swift`, `Tests/PokerNetTests/Helpers.swift`
- Create: `Tests/PokerNetTests/HostCardsTests.swift`

**Interfaces:**
- Consumes: `GameState.redacted(for:)`, `TournamentConfig.digitalCards`.
- Produces:
  - `broadcastState()` sends `snapshot.game.state.redacted(for: player)` to each bound connection
  - `Wire.version == 2`
  - Test helpers: `testSnapshot(digital: Bool = false)` (`.relaxed` with the flag set); `Table` moves from `HostCommandTests.swift` to `Helpers.swift`, becomes internal, and `Table.open` gains `snapshot: HostSnapshot = testSnapshot()`

- [ ] **Step 1: Write the failing tests** in `HostCardsTests.swift`

```swift
@Suite(.timeLimit(.minutes(1)))
struct HostCardsTests {
    @Test func clientsReceiveOnlyTheirOwnCards() async throws {
        let t = try await Table.open(snapshot: testSnapshot(digital: true))
        let ben = t.benWelcome.player
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        let seenByAnna = try await t.anna.state { $0.phase == .betting }
        let seenByBen = try await t.ben.state { $0.phase == .betting }
        let full = await t.host.snapshot.game.state
        #expect(full.deck.count == 48)
        #expect(seenByAnna.deck.isEmpty && seenByBen.deck.isEmpty)
        #expect(seenByAnna.seat(t.hostID)?.holeCards == full.seat(t.hostID)?.holeCards)
        #expect(seenByAnna.seat(ben)?.holeCards == [])
        #expect(seenByBen.seat(ben)?.holeCards == full.seat(ben)?.holeCards)
        #expect(seenByBen.seat(t.hostID)?.holeCards == [])
        await t.host.stop()
    }

    @Test func reconnectGetsOwnCardsAgain() async throws {
        let t = try await Table.open(snapshot: testSnapshot(digital: true))
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        _ = try await t.ben.state { $0.phase == .betting }
        let again = try await RawClient.connect(t.port)
        again.send(hello("Ben", token: t.benWelcome.token))
        let seen = try await again.state { $0.phase == .betting }
        let full = await t.host.snapshot.game.state
        #expect(seen.seat(t.benWelcome.player)?.holeCards == full.seat(t.benWelcome.player)?.holeCards)
        #expect(seen.seat(t.hostID)?.holeCards == [] && seen.deck.isEmpty)
        await t.host.stop()
    }
}
```

Add to `WireTests.swift`:

```swift
@Test func seatWithCardsGoldenJSON() throws {
    var seat = Seat(id: "A", name: "A", stack: 1000)
    seat.holeCards = cards("Ah Tc")
    #expect(json(try Wire.encoder.encode(seat)) ==
        #"{"acted":false,"allIn":false,"folded":false,"handBet":0,"holeCards":["Ah","Tc"],"id":"A","mayRaise":true,"name":"A","roundBet":0,"stack":1000,"stackAtHandStart":0}"#)
    let state = json(try Wire.encoder.encode(try Game.started().state))
    for field in [#""board":[]"#, #""deck":[]"#, #""digitalCards":false"#] { #expect(state.contains(field)) }
}
```

Also add a digital game's state to the messages of the existing `serverRoundTrip`, and replace every `"v":1` with `"v":2` in `WireTests.swift` (7) and `HostCommandTests.swift` (1).

- [ ] **Step 2: Run** `swift test --filter "HostCardsTests|WireTests"`. Expected: FAIL (`clientsReceiveOnlyTheirOwnCards` sees the other hand and a full deck; goldens expect `"v":2`).
- [ ] **Step 3: Implement** the redacted broadcast and `Wire.version = 2`.
- [ ] **Step 4: Update `Protocol.md`:**
  - Title "(version 2)"; every example envelope `"v":2`; in "Versions", one sentence that version 2 added the card fields.
  - `state` table: `config` row gains `digitalCards`; new rows `board[]` (community cards dealt so far; empty with real cards), `seats[].holeCards[]` (the receiver's own cards, and at showdown the hands still in play; otherwise empty), `deck` (always `[]` for clients).
  - New section "Cards" after the `state` table: the two-character format, rank characters `23456789TJQKA`, suit characters `c d h s`; the reveal rule from the spec; the note that clients derive the hand name themselves.
  - `resolveShowdown` row: with `digitalCards` the host pays out by itself, and the command is only needed after an `undo` returned the game to `showdown`.
  - `undo` row: in a digital game the first undo after a showdown returns to `showdown` before the payout.
  - "Security": the host device and its save file hold every card; a recorded handshake plus the brute-forced code exposes that player's hole cards.
- [ ] **Step 5: Run the gates:** `swift test`, `pre-commit run --all-files`, and the DocC build from `AGENTS.md`. Expected: all pass with no warnings.
- [ ] **Step 6: Commit** `feat(net)!: send each player a redacted state, protocol version 2`
- [ ] **Step 7: Open PR 1** from `feat/digital-cards-core`. Title `feat: digital cards in core and net (protocol v2)`. Body: links to spec and plan, ticked automatic gates, no manual checks, the note that version 1 clients and older host save files are refused.

---

### Task 7: Card views, theme tokens, card back setting

**Files:**
- Create: `App/Sources/CardViews.swift`
- Modify: `App/Sources/Theme.swift`, `App/Sources/SettingsView.swift`

**Interfaces:**
- Consumes: `Card`.
- Produces:
  - `Theme` tokens (felt / dark): `cardFrame` (`.white` / `0x3a3f4d`), `cardFace` (`0xf3e9d2` / `0x232733`), `cardText` (`.black` / `0xe8eaf0`), `cardRed` (`0xc0392b` / `0xff6b6b`)
  - `enum CardBack: String, CaseIterable` with `label` and `color`: `red` "Red" `0xb03a2e` (default), `blue` "Blue" `0x1f4e8c`, `green` "Green" `0x1e6b45`, `black` "Black" `0x1c1c1e`, `purple` "Purple" `0x5b3a8c`; stored as `@AppStorage("cardBack")`
  - `extension Card`: `symbol` (`♣ ♦ ♥ ♠`), `rankLabel` (`2`…`10`, `J`, `Q`, `K`, `A`), `isRed`, `spokenName` (e.g. "Ace of hearts")
  - `struct CardFaceView: View` (`card`, `width`), `struct CardBackView: View` (`back`, `width`), `struct CardSlotView: View` (`width`): aspect ratio 5:7, corner radius `width * 0.12`. The face shows the rank label above the symbol on `cardFace` with a `cardFrame` edge. The back is the base color with a `cardFrame` inner frame and a diamond lattice drawn in a `Canvas`. The slot is a `cardFrame` outline at 25 % opacity.
  - `struct CardsText: View` (`cards: [Card]`): one `Text` such as `A♥ K♠`, red cards in `cardRed`, with the spoken names as its accessibility label
  - `struct HoleCardsView: View` (`cards: [Card]`, `faceUp: Bool`, `width: CGFloat`): two cards side by side. Faces show while `faceUp`, while pressed (`@GestureState` updated by a `DragGesture(minimumDistance: 0)`), or after the accessibility action. Hidden: label "Your cards, hidden" and an accessibility action named "Show cards" that toggles a `@State` flag; shown: the label is the spoken names. The flag resets when `cards` changes.

- [ ] **Step 1: Implement** the tokens, `CardViews.swift`, and the "Card back" picker in `SettingsView` below "Appearance": one row per `CardBack` with a `CardBackView(width: 22)` and the label, in the same `Form`, with `.themedRow()`.
- [ ] **Step 2: Add a `#Preview`** in `CardViews.swift` showing a face, all five backs and a slot in both themes.
- [ ] **Step 3: Build the app** with the commands from `AGENTS.md`. Expected: build succeeds without warnings.
- [ ] **Step 4: Commit** `feat(app): card views, card theme tokens and a card back setting`

---

### Task 8: Table creation, host menu, debug

**Files:**
- Modify: `App/Sources/StartView.swift`, `App/Sources/LobbyView.swift`, `App/Sources/HostMenu.swift`, `App/Sources/DebugBots.swift`

**Interfaces:**
- Consumes: `TournamentConfig.digitalCards`, `GameState.isRevealed(_:)`.
- Produces:
  - `CreateTableSheet`: `@AppStorage("digitalCards") private var digitalCards = false`, a `Toggle("Digital cards", isOn:)` below the "Blinds" picker; `onCreate` receives the preset's config with `digitalCards` set
  - `StartView`'s `-debugTable` task: `.quick` with `digitalCards = UserDefaults.standard.bool(forKey: "digitalCards")`
  - `LobbyView` config line: append `" · digital cards"` when `state.config.digitalCards`
  - `HostConfirm.changeWinner`; in `HostMenu`, `Button("Change winner", systemImage: "trophy")` above "Undo last change", shown when `state.config.digitalCards`, the phase is `handComplete` or `finished`, and `state.seats.contains(where: state.isRevealed)`; in `hostConfirmation`, title "Undo the payout and pick the winners by hand?" and a destructive button "Change winner" that sends `.undo`
  - `DebugBots.autoStart`: the loop for `-debugStop showdown|payout` ends when the phase is `showdown` or, in a digital game, `handComplete` or `finished`; the manual `resolveShowdown` after it runs only when the phase is `showdown`. Update the doc comment of `stop`.

- [ ] **Step 1: Implement** the four changes.
- [ ] **Step 2: Build the app.** Expected: build succeeds without warnings.
- [ ] **Step 3: Check in the simulator:** create a table with "Digital cards" on, add bots in the lobby, play one hand to showdown, use "Change winner", pick another winner, "Pay out". Then relaunch with `-debugTable -debugStop showdown`. Expected: the lobby line shows "· digital cards"; the menu item appears only after a showdown; after "Change winner" the seat picks and "Pay out" work; the debug table is digital and stops at the first paid-out showdown. Cards are not drawn yet; Task 9 adds them.
- [ ] **Step 4: Commit** `feat(app): digital cards toggle, change winner and debug table`

---

### Task 9: Cards on the table

**Files:**
- Modify: `App/Sources/RoundTable.swift`, `App/Sources/TableView.swift`, `App/Sources/RankingView.swift`

**Interfaces:**
- Consumes: Task 7's views; `GameState.board`, `isRevealed(_:)`, `handValue(of:)`, `config.digitalCards`.
- Produces:
  - `RoundTable`, only when `state.config.digitalCards`:
    - a board row of 5 positions in the table center, `CardFaceView` for dealt cards and `CardSlotView` for the rest, card width `size.width * 0.085`, the row centered `size.width * 0.08` above the center, and the pot block moved the same distance below it; dealt cards enter with `.transition(.opacity)`
    - in `seatLabel`, a third row `CardsText(cards: seat.holeCards)` in `.caption2` when `state.isRevealed(seat)`
    - at `handComplete`, in place of the pot: one line `"\(seat.name) – \(value.name)"` per revealed seat with `seat.stack > seat.stackAtHandStart`, `.caption.bold()`, `lineLimit(1)`
    - those seats get the border and background of `SeatMark.selected` without the check mark; add `// ponytail: "won chips" stands in for "won a pot", so a side-pot winner who still lost chips overall is not marked; keep the winners in GameState if that matters`
  - `TableView`: the "Your stack" block becomes an `HStack(spacing: 16)` with `HoleCardsView(cards:, faceUp: state.isRevealed(mySeat), width: 50)` to its left, shown only when my seat holds 2 cards
  - `RankingView`: when `state.config.digitalCards` and any seat is revealed, a section "Final hand" below the ranking: a row of `CardFaceView(width: 34)` for the board, then per revealed seat a row with the name, `CardsText` and the hand name in `theme.muted`

- [ ] **Step 1: Implement** the three views as listed.
- [ ] **Step 2: Build the app.** Expected: build succeeds without warnings.
- [ ] **Step 3: Check the layout** on the iPhone SE (3rd generation) simulator: launch with `-debugTable` while "Digital cards" is stored on (Task 8), 10 seats. Expected with screenshots at preflop, flop, river and after a showdown: board, pot, bets and seat labels do not overlap, the table has the same size as on `feat/round-table`, the action bar with the raise slider is fully visible. Adjust the two `0.08`/`0.085` factors if needed and record the final values in the commit message.
- [ ] **Step 4: Commit** `feat(app): board, hole cards and revealed hands on the table`

---

### Task 10: Gates, manual checks, PR 2

**Files:**
- Modify: `README.md` (one sentence in the feature description: optional digital cards)

- [ ] **Step 1: Run the gates:** `pre-commit run --all-files`, `swift test`, the DocC build, the app build. Expected: all pass.
- [ ] **Step 2: Commit** `docs: mention digital cards in the README`
- [ ] **Step 3: Open PR 2** from `feat/digital-cards-app`. Title `feat(app): play with digital cards`. Body: links to spec and plan, the ticked automatic gates, and these manual checks unticked (iPhone, simulator as the second device):
  - Holding the hole cards shows them and releasing hides them; the VoiceOver action "Show cards" works.
  - A guest's phone never shows another player's cards before showdown.
  - Board, revealed hands and the winner line are right in Felt and Dark, including a hand with a side pot.
  - 10 players on an iPhone SE: nothing overlaps at any street or at showdown.
  - "Change winner" undoes the payout; picking a winner by hand pays out.
  - A tournament that ends at showdown shows "Final hand" in the ranking.
  - The card back picker changes the own hole cards in both themes.
  - A table with "Digital cards" off plays exactly as before, dealer hints included.
- [ ] **Step 4: Stop.** Merging waits until the user has ticked every manual check.
