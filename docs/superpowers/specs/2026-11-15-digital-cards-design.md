# Digital cards

Add an optional mode in which the app deals the cards: every player sees their own hole cards on their phone, the board appears on the table, and the host pays out the showdown automatically. Real cards stay the default. The mode touches `PokerCore` (cards, dealing, hand evaluation, redaction), `PokerNet` (per-player state), the wire protocol (version 2) and the app.

## Context

The players sit at the same table, each with their own iPhone, connected over Bonjour/AWDL as today. The mode is for a game night where nobody has a deck at hand or nobody wants to shuffle and deal. Remote play is out of scope. Play money only, as before.

The host device runs the game and may know every card. There is no protection against a cheating host: fair dealing without a trusted dealer (mental poker) would cost an order of magnitude more and is not worth it for a home game.

## Scope

In scope: cards and dealing, a hand evaluator, automatic showdown payout, per-player redaction of the broadcast state, protocol version 2, the table UI for cards, a card back setting, the host's "Change winner", and the debug table.

Out of scope: mucking or voluntarily showing cards, burn cards, other poker variants, remote play.

## Decisions

- The mode is chosen per table when it is created and holds for the whole tournament.
- Own hole cards are face down by default and face up only while the player holds a finger on them.
- At showdown all hands still in play are revealed to everyone. A player who wins because everyone else folded keeps their cards hidden.
- The host pays out at once. The host can undo the payout from the host menu ("Change winner") and pick the winners by hand.
- Cards live in `GameState`. The host sends every client a redacted copy (approach 1 of the brainstorm; a separate private message channel and a seeded deck were rejected as more code for no gain).
- The protocol goes to version 2 with required new fields. A host save file written by an older build no longer loads; that only matters for a crashed tournament resumed across an app update.

## PokerCore

### Types

- `Card` with `rank` (2…14, where 11 = J, 12 = Q, 13 = K, 14 = A) and `suit` (clubs, diamonds, hearts, spades). Encoded as a two-character string: rank `23456789TJQKA`, suit `cdhs`, e.g. `"Ah"`, `"Tc"`, `"2s"`. Any other string fails to decode.
- `TournamentConfig.digitalCards: Bool`, default `false`. The presets stay; the flag is set on top of a preset.
- `Seat.holeCards: [Card]`, `GameState.board: [Card]`, `GameState.deck: [Card]` (the cards not yet dealt). All three are empty with real cards.

### Dealing (only with `digitalCards`)

- `startHand()` shuffles a full 52-card deck and gives every seat that is not eliminated 2 cards. `board` is emptied.
- `endRound()` deals 3 cards to the board when the street moves to the flop, 1 for the turn and 1 for the river.
- `enterShowdown()` deals the board up to 5 cards before the pots are formed, so an all-in run-out shows every card.
- Shuffling uses an injected `RandomNumberGenerator`; production passes `SystemRandomNumberGenerator`, tests a seeded generator. Undo restores the deck with the state, so undo never re-deals different cards.
- The deck cannot run out: at most 10 × 2 + 5 = 25 of 52 cards are used. A comment states this; no runtime check.

### Revealed hands

No extra field. Hole cards of a seat are public when the phase is `showdown`, `handComplete` or `finished`, at least 2 seats have not folded, and the seat has not folded. After a fold win only one seat is left, so nothing is revealed. A player removed mid-hand counts as folded and is never revealed.

### Hand evaluator

- `HandValue: Comparable`: a category (high card, pair, two pair, three of a kind, straight, flush, full house, four of a kind, straight flush) plus the ranks that break ties, in order.
- `evaluate(_ cards: [Card]) -> HandValue` takes 5 to 7 cards and returns the best 5-card hand by checking every 5-card combination (21 for 7 cards).
- The ace plays low in the wheel `A-2-3-4-5`, which is the lowest straight.
- Each category has a display name ("Flush", "Full house", …); a straight flush to the ace is shown as "Royal flush". Clients compute the name themselves from the revealed cards and the board.

### Automatic payout

- In `Game.apply`, when a command moves a digital game from another phase into `showdown`, the showdown state is pushed onto `history` as its own entry, and then `resolveShowdown` runs with the winners from the evaluator.
- Winners of a pot: every `eligible` player whose `HandValue` equals the highest in that pot. Chips are split with the existing `split(...)`, odd chips included.
- `undo` after the automatic payout therefore returns to `showdown` with the pots and revealed hands. From there `resolveShowdown` works as it does with real cards. This also holds when the payout ended the tournament (`finished`).
- `resolveShowdown` stays allowed in digital games, for the path after an undo.

### Redaction

`GameState.redacted(for viewer: PlayerID?) -> GameState`, a pure function: `deck` becomes `[]`, and `holeCards` is emptied on every seat except the viewer's own and except revealed seats. A `nil` viewer sees no hole cards except revealed ones. The undo history is never sent and needs no redaction.

### Dealer hint

`dealerHint` returns `nil` in digital games: there is nothing to deal by hand.

## PokerNet

- `TableHost.broadcastState()` sends each bound connection `state.redacted(for: player)`. It is the only place that sends `state`; the welcome path goes through it.
- The host device joins its own table over loopback, so its UI receives the redacted state as well and never shows other players' cards.
- `Wire.version` becomes 2.

## Protocol (`Sources/PokerNet/PokerNet.docc/Protocol.md`)

Updated in the same PR as the wire change:

- Version 2 in the title and the envelope examples. A peer that speaks version 1 gets `versionMismatch`.
- `state` table: `config.digitalCards`, `board[]`, `seats[].holeCards[]` (own cards, or revealed cards at showdown), `deck` (always `[]` for clients).
- The card string format (rank and suit characters).
- `resolveShowdown`: with `digitalCards` the host pays out by itself; clients only send it after an undo returned the game to `showdown`.
- Security: the host device and its save file know every card. Anyone who records a player's traffic and brute-forces the 4-digit code (the known PSK weakness) can read that player's hole cards.

## App

### Creating a table

- `CreateTableSheet` gets a "Digital cards" toggle below "Blinds", stored as `@AppStorage("digitalCards")` (default off), so the last choice is remembered.
- The lobby's config line adds "· digital cards" when the flag is on, e.g. `1000 chips · 10 min levels · digital cards`.

### Board

Five card slots in the center of `RoundTable`, above the pot. Empty slots are a faint outline, so the layout does not jump. Card size scales with the table like the seat labels. New cards fade in.

With 10 seats the bets on their usual ring, halfway between seat and center, would cover the board. In digital games a seat's bet is therefore shown as the third row of its seat label while betting, and no bets are drawn in the center; real-card games keep today's bets.

### Own hole cards

- Two large cards in the same row as "Your stack", to its left, face down by default. The row keeps its height, so the table keeps its size on an iPhone SE.
- Pressing and holding shows them; releasing hides them again (a pressing gesture state, not a tap toggle).
- From showdown on they are face up anyway.
- VoiceOver: the label is "Your cards, hidden"; the accessibility action "Show cards" reveals and reads them.

### Showdown

- Revealed hands appear as a third row in the seat label, compact as `A♥ K♠`. ♥ and ♦ use the theme's red. One extra row is the limit: with 10 seats on an iPhone SE a fourth row would touch the neighbouring label.
- After the payout the table center, where the pot is empty by then, shows the winning hand type above the board and the winner names below it, e.g. "Flush" above and "Anna" below. Several winners are joined ("Anna, Ben"), and different winning hands too ("Flush · Two pair"). A seat won when its stack is above its stack at hand start.
- Those seats also get the accent border, as when picking winners today.
- In every game, real or digital, the amount a seat won or lost in the hand (the green or red delta after the stack) is always shown in full and never cut to "…". The row shrinks instead, or shows only the delta in place of the stack until the next hand starts; only the name may be truncated.

### Final hand

When the payout ends the tournament, the app switches to the ranking at once, so the table never shows the last showdown. In digital games `RankingView` therefore gets a "Final hand" section below the ranking: the board, and one row per revealed seat with its name, cards and hand name.

### Host menu

- "Change winner" appears in digital games when the phase is `handComplete` or `finished` and hands are revealed.
- It asks first: "Undo the payout and pick the winners by hand?" Then it sends `.undo`.
- The game is back in the existing `ShowdownView` with tap-to-pick on the table and "Pay out".

### Card backs

- `SettingsView` gets a "Card back" picker below "Appearance", stored per device as `@AppStorage("cardBack")`.
- Five backs with the same classic pattern (base color, a thin inner frame and a fine diamond lattice, drawn with `Canvas`): Red (default), Blue, Green, Black, Purple. Each row shows a small preview.

### Theme tokens

New tokens in `Theme`:

| Token | Felt | Dark |
|---|---|---|
| `cardFrame` (inner frame and lattice of the back, edge of the face) | white | `0x3a3f4d` |
| `cardFace` (face background) | `0xf3e9d2` | `0x232733` |
| `cardText` (rank and ♣♠) | black | `0xe8eaf0` |
| `cardRed` (♥♦) | `0xc0392b` | `0xff6b6b` |

The base colors of the card backs are the same in both themes. The dark theme has no white on cards.

### Debug

- No new launch argument. Debug bots are configured in the lobby as today; a digital game with bots is created with the "Digital cards" toggle and "Add bots".
- `-debugTable` uses the stored `digitalCards` value instead of always real cards.
- `-debugStop showdown|payout` in a digital game: there is no stop before the payout, so both stop at the first `handComplete` with revealed hands.

## Testing

### Core tests

- `CardTests`: `"Ah"` round-trips; `"1x"`, `"A"` and `"Ahh"` fail to decode.
- `EvaluatorTests`: one hand per category and the order of categories; kickers decide within a category; the wheel loses to a six-high straight; the best 5 of 7 cards is found; a board that plays splits the pot.
- `DealingTests` (seeded generator): every seat not eliminated holds 2 cards; the board holds 0, 3, 4, 5 cards on preflop, flop, turn, river; an all-in run-out deals 5; seats, board and deck together hold exactly 52 distinct cards.
- `AutoShowdownTests`: a side pot goes to a different winner than the main pot; a split pot gives the odd chip through `split`; a fold win reveals nothing; `undo` after the payout returns to `showdown` with the same pots, and `resolveShowdown` then pays as given; a payout that ends the tournament can be undone the same way.
- `RedactionTests`: the deck is always empty; other players' cards are hidden and the own ones shown; at showdown hands in play are revealed and folded ones are not; a `nil` viewer sees only revealed hands.
- `dealerHint` is `nil` in digital games.
- Existing tests run unchanged with `digitalCards: false`. The chip conservation test also runs in digital mode.

### Net tests

- Two real clients at a host with a digital tournament: client A receives its own hole cards, not B's, and `deck == []`. A reconnecting client receives its own cards again.
- Wire golden tests move to `"v":2`; one new golden test covers a state with cards.

### Manual checks (iPhone, simulator as the second device)

- Holding the cards shows them, releasing hides them; VoiceOver action works.
- Board and showdown display in both themes, including a side pot.
- The ranking shows the final hand after a tournament that ends at showdown.
- "Change winner" undoes the payout and the manual payout works.
- Card back picker in Settings, in both themes.
- `-debugTable` with "Digital cards" stored on and off.

## Delivery

Two PRs, one plan. The work builds on `feat/round-table`, whose round table leaves the room the cards need:

1. Core, Net and protocol. Fully covered by `swift test`, no manual checks. `main` stays usable: without the toggle the app runs with `digitalCards: false`.
2. App: UI, settings, host menu and debug, with the manual checks.
