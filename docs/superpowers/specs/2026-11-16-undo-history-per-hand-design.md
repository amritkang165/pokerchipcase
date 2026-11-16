# Undo history per hand

Issue: #109.

## Why

`TableHost.handle` saves the whole `HostSnapshot` before it broadcasts and acks a command. The snapshot holds `Game.history`, every state since the tournament started (about 42 per hand with ten players). After 200 hands that is 8,410 states, a 22.1 MB `host.json` and 0.258 s per save, so every command waits about a quarter second and the host app stalls.

## Goal

Keep the save small and constant over a tournament by keeping only the current hand in the undo history.

## Non-goals

- No change to when the host saves (still before broadcast and ack, so a crash never loses an acked command).
- No journal or incremental save.
- No wire change. The handover still carries at most `TableHost.handoverHistory` (50) steps.

## Approaches

- **(a) Undo within the current hand only. Picked.** When a command starts a new hand, the history keeps only the previous hand's last step and the state just before the new hand. The file stays at the size of one hand (about 0.1 MB with ten players). A mistake in an earlier hand can no longer be undone.
- (b) A fixed cap, e.g. the newest 200 states (4 to 5 hands). This allows a deeper undo but the file is about 0.5 MB and the cap is an arbitrary number.
- (c) Save after the broadcast and ack. This removes the wait but not the growth. A crash right after an ack would leave clients ahead of the resumed host.

## Design

- In `Game.apply` (PokerCore): if the new state's `handNumber` is greater than the old one, set `history` to the previous hand's last step plus the command's own steps, instead of appending. This covers `startTournament` (hand 1) and `startNextHand`.
- Undo can therefore take back the deal of the new hand, back to `handComplete`, and then once more the previous hand's payout. That keeps "Change winner" working after undoing the deal: the menu offers it in any `handComplete` with revealed hands. One step further gives `nothingToUndo`. (Revised after the final review: the first version kept only the state before the deal, so "Change winner" failed there.)
- Lobby history (joins, removals) is dropped when the tournament starts, except the last two lobby states.
- An existing large save shrinks at the next hand start. No migration.
- Docs: README "Undo for the host" gets "back to the previous hand's payout"; the `undo` row in `Protocol.md` says the same.

## Tests

- PokerCoreTests: after `startNextHand`, `history.count == 2`; undo returns to `handComplete`, then to `showdown`, a third throws `nothingToUndo`.
- PokerCoreTests: after `startTournament`, `history` holds the last two lobby states.
- Optional: `-debugLongGame` prints the new file size and save time on a device.

## Left to the builder

The exact test names and where the check sits inside `apply`.
